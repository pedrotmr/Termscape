import AppKit
import Bonsplit
import QuartzCore

/// NSView that positions terminal surface views absolutely based on the Bonsplit layout.
final class CanvasDocumentView: NSView {
    private var hostedViews: [String: GhosttySurfaceScrollView] = [:]
    private var dividerViews: [String: PaneDividerView] = [:]

    /// Retained during a context menu interaction so the Clear action can reach the focused surface.
    private weak var contextMenuTab: WorkspaceTab?
    private weak var currentTab: WorkspaceTab?

    private var currentCanvasBackground: NSColor = NSColor(red: 0.125, green: 0.118, blue: 0.110, alpha: 1)
    private var currentAccentColor: NSColor = NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85)

    private struct HorizontalDragState {
        let tree: ExternalTreeNode
        let firstNode: ExternalTreeNode
        let firstPaneIds: Set<String>
        let baselinePaneWidths: [String: CGFloat]
        let firstWidth: CGFloat
    }

    #if DEBUG
    private struct DragTelemetry {
        var startTime: CFTimeInterval
        var lastSampleTime: CFTimeInterval
        var sampleCount: Int
        var worstGap: CFTimeInterval
    }
    #endif

    private var horizontalDragStateBySplitId: [String: HorizontalDragState] = [:]
    #if DEBUG
    private var dragTelemetryBySplitId: [String: DragTelemetry] = [:]
    #endif

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Manual frame defines canvas size for NSScrollView; avoid autoresizing that pins width to the clip view.
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = []
        layer?.backgroundColor = currentCanvasBackground.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Theme

    func applyTheme(canvasBackground: NSColor, accentColor: NSColor) {
        currentCanvasBackground = canvasBackground
        layer?.backgroundColor = canvasBackground.cgColor
        currentAccentColor = accentColor

        for (_, view) in hostedViews {
            let isFocused = view.layer?.borderWidth == 1.5
            if isFocused {
                view.layer?.borderColor = accentColor.withAlphaComponent(0.85).cgColor
            }
            view.setBackgroundColor(canvasBackground)
        }

        for (_, divider) in dividerViews {
            divider.accentColor = accentColor
        }
    }

    // MARK: - Layout update

    /// Lays out terminal panes. Returns the focused pane’s frame in this document view’s coordinates (for scroll-to-visible).
    @discardableResult
    func update(tab: WorkspaceTab, viewportSize: CGSize) -> CGRect? {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }
        currentTab = tab
        tab.rebalanceThreePaneHorizontalWidthsForStretchMode(viewportWidth: viewportSize.width)

        let canvasWidth = max(tab.canvasWidth <= 0 ? viewportSize.width : tab.canvasWidth, 1)
        let canvasSize = CGSize(width: canvasWidth, height: viewportSize.height)
        frame = CGRect(origin: .zero, size: canvasSize)
        tab.bonsplitController.setContainerFrame(CGRect(origin: .zero, size: canvasSize))

        let tree = tab.bonsplitController.treeSnapshot()
        let snapshot = tab.bonsplitController.layoutSnapshot()
        let isMultiPane = snapshot.panes.count > 1

        var activePaneIds = Set<String>()
        var focusedRect: CGRect?

        for pane in snapshot.panes {
            activePaneIds.insert(pane.paneId)
            let rawFrame = CGRect(
                x: pane.frame.x,
                y: pane.frame.y,
                width: pane.frame.width,
                height: pane.frame.height
            )
            let displayFrame = pixelAlignedFrame(rawFrame)
            let isFocused = pane.paneId == snapshot.focusedPaneId

            guard let selectedTabIdStr = pane.selectedTabId,
                  let selectedTabUUID = UUID(uuidString: selectedTabIdStr) else { continue }

            let surface: TerminalSurface
            if let existing = tab.surfaces[selectedTabUUID] {
                surface = existing
            } else {
                let tabId = TabID(uuid: selectedTabUUID)
                surface = tab.createSurface(for: tabId)
            }

            let hostedView: GhosttySurfaceScrollView
            if let existing = hostedViews[pane.paneId], existing === surface.hostedView {
                hostedView = existing
            } else {
                hostedViews[pane.paneId]?.removeFromSuperview()
                hostedView = surface.hostedView
                hostedViews[pane.paneId] = hostedView
                hostedView.setBackgroundColor(currentCanvasBackground)
                addSubview(hostedView)

                // Wire callbacks only when attaching a new view (avoid allocation churn per layout pass).
                let paneIdStr = pane.paneId
                hostedView.surfaceView.onFocused = { [weak tab] in
                    guard let tab, let paneUUID = UUID(uuidString: paneIdStr) else { return }
                    tab.bonsplitController.focusPane(PaneID(id: paneUUID))
                }

                hostedView.surfaceView.onContextMenu = { [weak self, weak tab] event in
                    guard let self, let tab else { return }
                    self.contextMenuTab = tab
                    NSMenu.popUpContextMenu(self.buildContextMenu(isMultiPane: isMultiPane), with: event, for: self)
                }
            }

            hostedView.frame = displayFrame
            applyBorder(to: hostedView, focused: isFocused, multiPane: isMultiPane)

            // Deliver any pending input (e.g. clone command) once the surface exists.
            if let pending = tab.pendingInputOnceAttached, surface.surface != nil {
                surface.sendText(pending)
                tab.pendingInputOnceAttached = nil
            }

            if isFocused {
                focusedRect = displayFrame
            }
        }

        let removed = Set(hostedViews.keys).subtracting(activePaneIds)
        for paneId in removed {
            hostedViews[paneId]?.removeFromSuperview()
            hostedViews.removeValue(forKey: paneId)
        }

        let dividerDescriptors = computeDividers(
            from: tree,
            region: CGRect(origin: .zero, size: canvasSize)
        )
        let activeSplitIds = Set(dividerDescriptors.map(\.splitId))

        for descriptor in dividerDescriptors {
            let dividerView: PaneDividerView
            if let existing = dividerViews[descriptor.splitId] {
                dividerView = existing
            } else {
                let created = PaneDividerView(frame: descriptor.frame)
                created.accentColor = currentAccentColor
                let splitId = descriptor.splitId
                let splitOrientation = descriptor.orientation
                created.onPressFocus = { [weak self] focusSide in
                    self?.focusPaneForDividerInteraction(splitId: splitId, focusSide: focusSide)
                }
                created.onDragBegan = { [weak self] focusSide in
                    self?.handleDividerDragBegan(
                        splitId: splitId,
                        orientation: splitOrientation,
                        focusSide: focusSide
                    )
                }
                created.onDragDeltaPixels = { [weak self] deltaPixels in
                    self?.handleDividerDragDeltaPixels(
                        splitId: splitId,
                        orientation: splitOrientation,
                        deltaPixels: deltaPixels
                    )
                }
                created.onDrag = { [weak self] newPosition in
                    self?.handleDividerDragNormalized(
                        splitId: splitId,
                        orientation: splitOrientation,
                        newPosition: newPosition
                    )
                }
                created.onDragEnd = { [weak self] didDrag, focusSide in
                    self?.handleDividerDragEnd(
                        splitId: splitId,
                        orientation: splitOrientation,
                        didDrag: didDrag,
                        focusSide: focusSide
                    )
                }
                dividerViews[descriptor.splitId] = created
                dividerView = created
                addSubview(dividerView)
            }

            dividerView.frame = descriptor.frame
            dividerView.orientation = descriptor.orientation
            dividerView.position = descriptor.position
            dividerView.parentSpanInDragAxis = descriptor.parentSpanInDragAxis
            dividerView.minPosition = descriptor.minPosition
            dividerView.maxPosition = descriptor.maxPosition
            addSubview(dividerView, positioned: .above, relativeTo: nil)
        }

        let removedDividers = Set(dividerViews.keys).subtracting(activeSplitIds)
        for splitId in removedDividers {
            dividerViews[splitId]?.removeFromSuperview()
            dividerViews.removeValue(forKey: splitId)
            horizontalDragStateBySplitId.removeValue(forKey: splitId)
            #if DEBUG
            dragTelemetryBySplitId.removeValue(forKey: splitId)
            #endif
        }

        return focusedRect
    }

    // MARK: - Helpers

    private struct DividerDescriptor {
        let splitId: String
        let frame: CGRect
        let orientation: PaneDividerView.Orientation
        let position: CGFloat
        let parentSpanInDragAxis: CGFloat
        let minPosition: CGFloat
        let maxPosition: CGFloat
    }

    private enum SplitAxis {
        case horizontal
        case vertical
    }

    private enum DividerBranch {
        case first
        case second
    }

    private func handleDividerDragBegan(
        splitId: String,
        orientation: PaneDividerView.Orientation,
        focusSide: PaneDividerView.FocusSide
    ) {
        _ = focusSide
        guard orientation == .horizontal else { return }
        guard let tab = currentTab else { return }

        let tree = tab.bonsplitController.treeSnapshot()
        guard let split = HorizontalPaneSizingEngine.findSplit(in: tree, splitId: splitId) else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let paneWidths = HorizontalPaneSizingEngine.paneWidths(from: snapshot)
        let firstPaneIds = HorizontalPaneSizingEngine.paneIDs(in: split.first)
        let firstWidth = subtreeWidth(for: split.first, paneWidths: paneWidths)
        guard firstWidth > 0 else { return }

        horizontalDragStateBySplitId[splitId] = HorizontalDragState(
            tree: tree,
            firstNode: split.first,
            firstPaneIds: firstPaneIds,
            baselinePaneWidths: paneWidths,
            firstWidth: firstWidth
        )

        #if DEBUG
        let now = CACurrentMediaTime()
        dragTelemetryBySplitId[splitId] = DragTelemetry(
            startTime: now,
            lastSampleTime: now,
            sampleCount: 0,
            worstGap: 0
        )
        #endif
    }

    private func focusPaneForDividerInteraction(splitId: String, focusSide: PaneDividerView.FocusSide) {
        guard let tab = currentTab else { return }
        let tree = tab.bonsplitController.treeSnapshot()
        guard let split = HorizontalPaneSizingEngine.findSplit(in: tree, splitId: splitId) else { return }

        let branch: DividerBranch = (focusSide == .first) ? .first : .second
        let targetNode: ExternalTreeNode = (branch == .first) ? split.first : split.second
        let targetPaneIds = HorizontalPaneSizingEngine.paneIDs(in: targetNode)
        guard !targetPaneIds.isEmpty else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let targetPaneId: String?
        if let focusedPaneId = snapshot.focusedPaneId, targetPaneIds.contains(focusedPaneId) {
            targetPaneId = focusedPaneId
        } else {
            targetPaneId = snapshot.panes.first(where: { targetPaneIds.contains($0.paneId) })?.paneId
                ?? targetPaneIds.sorted().first
        }

        guard let targetPaneId,
              let paneUUID = UUID(uuidString: targetPaneId)
        else { return }
        tab.bonsplitController.focusPane(PaneID(id: paneUUID))
    }

    private func handleDividerDragDeltaPixels(
        splitId: String,
        orientation: PaneDividerView.Orientation,
        deltaPixels: CGFloat
    ) {
        guard orientation == .horizontal else { return }
        guard let tab = currentTab,
              let state = horizontalDragStateBySplitId[splitId] else { return }

        let interactiveMinimum = tab.bonsplitController.configuration.appearance.minimumPaneWidth
        let minimumFirstWidth = HorizontalPaneSizingEngine.minimumRequiredWidth(
            for: state.firstNode,
            minimumPaneWidth: interactiveMinimum
        )

        var targetFirstWidth = state.firstWidth + deltaPixels
        let clampFloor = state.firstWidth >= minimumFirstWidth ? minimumFirstWidth : state.firstWidth
        targetFirstWidth = max(targetFirstWidth, clampFloor)

        guard targetFirstWidth > 0, state.firstWidth > 0 else { return }

        let scale = targetFirstWidth / state.firstWidth
        var desiredPaneWidths = state.baselinePaneWidths
        for paneId in state.firstPaneIds {
            if let baselineWidth = state.baselinePaneWidths[paneId] {
                desiredPaneWidths[paneId] = max(baselineWidth * scale, 1)
            }
        }

        let plan = HorizontalPaneSizingEngine.buildPlan(
            tree: state.tree,
            desiredPaneWidths: desiredPaneWidths,
            fallbackPaneWidth: interactiveMinimum
        )

        applyHorizontalSizingPlan(plan, to: tab)
        (enclosingScrollView as? CanvasScrollView)?.updateLayout(for: tab, options: [])

        #if DEBUG
        if var telemetry = dragTelemetryBySplitId[splitId] {
            let now = CACurrentMediaTime()
            let gap = now - telemetry.lastSampleTime
            telemetry.worstGap = max(telemetry.worstGap, gap)
            telemetry.lastSampleTime = now
            telemetry.sampleCount += 1
            dragTelemetryBySplitId[splitId] = telemetry
        }
        #endif
    }

    private func handleDividerDragNormalized(
        splitId: String,
        orientation: PaneDividerView.Orientation,
        newPosition: CGFloat
    ) {
        guard orientation == .vertical else { return }
        guard let tab = currentTab, let splitUUID = UUID(uuidString: splitId) else { return }
        guard tab.bonsplitController.setDividerPosition(newPosition, forSplit: splitUUID) else { return }
        (enclosingScrollView as? CanvasScrollView)?.updateLayout(for: tab, options: [])
    }

    private func handleDividerDragEnd(
        splitId: String,
        orientation: PaneDividerView.Orientation,
        didDrag: Bool,
        focusSide: PaneDividerView.FocusSide
    ) {
        if didDrag {
            focusPaneForDividerInteraction(splitId: splitId, focusSide: focusSide)
        }
        if orientation == .horizontal {
            horizontalDragStateBySplitId.removeValue(forKey: splitId)

            #if DEBUG
            if let telemetry = dragTelemetryBySplitId.removeValue(forKey: splitId) {
                let elapsed = max(telemetry.lastSampleTime - telemetry.startTime, 0.0001)
                let hz = Double(telemetry.sampleCount) / elapsed
                let worstGapMs = telemetry.worstGap * 1000
                print(
                    "divider.drag.metrics split=\(splitId.prefix(6)) samples=\(telemetry.sampleCount) " +
                    "elapsedMs=\(String(format: "%.1f", elapsed * 1000)) " +
                    "hz=\(String(format: "%.1f", hz)) maxGapMs=\(String(format: "%.1f", worstGapMs))"
                )
            }
            #endif
        }

        currentTab?.notifyLayoutChanged()
    }

    private func applyHorizontalSizingPlan(_ plan: HorizontalSizingPlan, to tab: WorkspaceTab) {
        for (splitId, position) in plan.splitPositions {
            _ = tab.bonsplitController.setDividerPosition(position, forSplit: splitId)
        }
        tab.canvasWidth = max(plan.rootWidth, 1)
    }

    private func subtreeWidth(for node: ExternalTreeNode, paneWidths: [String: CGFloat]) -> CGFloat {
        switch node {
        case .pane(let pane):
            return max(paneWidths[pane.id] ?? WorkspaceTab.interactiveMinimumPaneWidth, 1)
        case .split(let split):
            let first = subtreeWidth(for: split.first, paneWidths: paneWidths)
            let second = subtreeWidth(for: split.second, paneWidths: paneWidths)
            return split.orientation == "horizontal" ? (first + second) : max(first, second)
        }
    }

    private func computeDividers(from node: ExternalTreeNode, region: CGRect) -> [DividerDescriptor] {
        switch node {
        case .pane:
            return []
        case .split(let split):
            let orientation: PaneDividerView.Orientation = split.orientation == "horizontal" ? .horizontal : .vertical
            let axis: SplitAxis = split.orientation == "horizontal" ? .horizontal : .vertical

            let firstRegion: CGRect
            let secondRegion: CGRect
            let dividerFrame: CGRect
            let parentSpan: CGFloat
            let bounds = clampedDividerBounds(
                first: split.first,
                second: split.second,
                axis: axis,
                parentSpan: split.orientation == "horizontal" ? max(region.width, 1) : max(region.height, 1)
            )
            let position = CGFloat(split.dividerPosition).clamped(to: bounds)

            if split.orientation == "horizontal" {
                let dividerEdge = (region.minX + (region.width * position)).rounded()
                firstRegion = CGRect(
                    x: region.minX,
                    y: region.minY,
                    width: max(dividerEdge - region.minX, 0),
                    height: region.height
                )
                secondRegion = CGRect(
                    x: dividerEdge,
                    y: region.minY,
                    width: max(region.maxX - dividerEdge, 0),
                    height: region.height
                )
                dividerFrame = CGRect(
                    x: dividerEdge - PaneDividerView.hitThickness / 2,
                    y: region.minY,
                    width: PaneDividerView.hitThickness,
                    height: region.height
                )
                parentSpan = max(region.width, 1)
            } else {
                let dividerEdge = (region.minY + (region.height * position)).rounded()
                firstRegion = CGRect(
                    x: region.minX,
                    y: region.minY,
                    width: region.width,
                    height: max(dividerEdge - region.minY, 0)
                )
                secondRegion = CGRect(
                    x: region.minX,
                    y: dividerEdge,
                    width: region.width,
                    height: max(region.maxY - dividerEdge, 0)
                )
                dividerFrame = CGRect(
                    x: region.minX,
                    y: dividerEdge - PaneDividerView.hitThickness / 2,
                    width: region.width,
                    height: PaneDividerView.hitThickness
                )
                parentSpan = max(region.height, 1)
            }

            let descriptor = DividerDescriptor(
                splitId: split.id,
                frame: dividerFrame,
                orientation: orientation,
                position: position,
                parentSpanInDragAxis: parentSpan,
                minPosition: bounds.lowerBound,
                maxPosition: bounds.upperBound
            )
            return [descriptor]
                + computeDividers(from: split.first, region: firstRegion)
                + computeDividers(from: split.second, region: secondRegion)
        }
    }

    private func clampedDividerBounds(
        first: ExternalTreeNode,
        second: ExternalTreeNode,
        axis: SplitAxis,
        parentSpan: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard parentSpan > 0 else { return 0...1 }

        let firstRequested = minimumRequiredSize(for: first, axis: axis)
        let secondRequested = minimumRequiredSize(for: second, axis: axis)

        let totalRequested = firstRequested + secondRequested
        let firstMinimum: CGFloat
        let secondMinimum: CGFloat
        if totalRequested > parentSpan, totalRequested > 0 {
            let scale = parentSpan / totalRequested
            firstMinimum = firstRequested * scale
            secondMinimum = secondRequested * scale
        } else {
            firstMinimum = firstRequested
            secondMinimum = secondRequested
        }

        var minPosition = max(0, firstMinimum / parentSpan)
        var maxPosition = min(1, 1 - (secondMinimum / parentSpan))
        if minPosition > maxPosition {
            let midpoint = ((minPosition + maxPosition) / 2).clamped(to: 0...1)
            minPosition = midpoint
            maxPosition = midpoint
        }
        return minPosition...maxPosition
    }

    private func minimumRequiredSize(for node: ExternalTreeNode, axis: SplitAxis) -> CGFloat {
        switch node {
        case .pane:
            switch axis {
            case .horizontal:
                return currentTab?.bonsplitController.configuration.appearance.minimumPaneWidth
                    ?? WorkspaceTab.interactiveMinimumPaneWidth
            case .vertical:
                return currentTab?.bonsplitController.configuration.appearance.minimumPaneHeight
                    ?? WorkspaceTab.interactiveMinimumPaneHeight
            }
        case .split(let split):
            let first = minimumRequiredSize(for: split.first, axis: axis)
            let second = minimumRequiredSize(for: split.second, axis: axis)
            let matchesAxis = (axis == .horizontal && split.orientation == "horizontal")
                || (axis == .vertical && split.orientation == "vertical")
            return matchesAxis ? (first + second) : max(first, second)
        }
    }

    private func pixelAlignedFrame(_ frame: CGRect) -> CGRect {
        let minX = floor(frame.minX)
        let minY = floor(frame.minY)
        let maxX = ceil(frame.maxX)
        let maxY = ceil(frame.maxY)
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }

    private func applyBorder(to view: GhosttySurfaceScrollView, focused: Bool, multiPane: Bool) {
        view.wantsLayer = true
        guard multiPane else {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            return
        }
        if focused {
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = currentAccentColor.withAlphaComponent(0.85).cgColor
        } else {
            view.layer?.borderWidth = 0.5
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }

    // MARK: - Context menu

    private func buildContextMenu(isMultiPane: Bool) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        menu.addItem(makeItem("Split Horizontally", icon: "rectangle.split.2x1", action: #selector(menuSplitRight(_:))))
        menu.addItem(makeItem("Split Vertically",   icon: "rectangle.split.1x2", action: #selector(menuSplitDown(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem("New Tab",             icon: "plus.rectangle",      action: #selector(menuNewTab(_:))))
        if isMultiPane {
            menu.addItem(makeItem("Move to New Tab", icon: "arrow.up.right.square", action: #selector(menuMoveToNewTab(_:))))
        }
        menu.addItem(.separator())
        let clearItem = makeItem("Clear", icon: "eraser.fill", action: #selector(menuClear(_:)))
        clearItem.keyEquivalent = "k"
        clearItem.keyEquivalentModifierMask = .command
        menu.addItem(clearItem)
        let closeTitle = isMultiPane ? "Close Pane" : "Close Tab"
        menu.addItem(makeItem(closeTitle,            icon: "xmark",                action: #selector(menuClose(_:))))

        return menu
    }

    private func makeItem(_ title: String, icon: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        return item
    }

    @objc private func menuSplitRight(_ sender: Any?) {
        NotificationCenter.default.post(name: .splitRight, object: nil)
    }

    @objc private func menuSplitDown(_ sender: Any?) {
        NotificationCenter.default.post(name: .splitDown, object: nil)
    }

    @objc private func menuNewTab(_ sender: Any?) {
        NotificationCenter.default.post(name: .newTab, object: nil)
    }

    @objc private func menuMoveToNewTab(_ sender: Any?) {
        guard let tab = contextMenuTab else { return }
        let snapshot = tab.bonsplitController.layoutSnapshot()
        guard let focusedPaneId = snapshot.focusedPaneId,
              let pane = snapshot.panes.first(where: { $0.paneId == focusedPaneId }),
              let selectedTabId = pane.selectedTabId,
              let tabUUID = UUID(uuidString: selectedTabId),
              let surface = tab.surfaces.removeValue(forKey: tabUUID)
        else { return }

        // Close the source pane if it's not the only one.
        // (For single-pane, the workspace tab itself is closed by the notification handler.)
        let isSinglePane = tab.bonsplitController.allPaneIds.count == 1
        if !isSinglePane, let paneUUID = UUID(uuidString: focusedPaneId) {
            tab.bonsplitController.closePane(PaneID(id: paneUUID))
        }

        let key = Notification.Name.MoveToNewTabKey.self
        NotificationCenter.default.post(
            name: .moveToNewTab,
            object: nil,
            userInfo: [
                key.surface: surface,
                key.sourceTab: tab,
                key.closeSourceTab: isSinglePane
            ]
        )
    }

    @objc private func menuClose(_ sender: Any?) {
        NotificationCenter.default.post(name: .closeTab, object: nil)
    }

    @objc private func menuClear(_ sender: Any?) {
        guard let tab = contextMenuTab else { return }
        let snapshot = tab.bonsplitController.layoutSnapshot()
        guard let focusedPaneId = snapshot.focusedPaneId,
              let pane = snapshot.panes.first(where: { $0.paneId == focusedPaneId }),
              let selectedTabId = pane.selectedTabId,
              let tabUUID = UUID(uuidString: selectedTabId),
              let surface = tab.surfaces[tabUUID]
        else { return }
        surface.performClearScreen()
    }
}
