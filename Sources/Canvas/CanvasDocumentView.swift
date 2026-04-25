import AppKit
import Bonsplit
import QuartzCore
import SwiftUI

/// NSView that positions pane content views absolutely based on the Bonsplit layout.
@MainActor
final class CanvasDocumentView: NSView {
    private struct HostedPaneView {
        let containerView: NSView
        let contentView: NSView
        let focusView: NSView
        let kind: WorkspacePaneContentKind
        let applyTheme: (AppTheme) -> Void
        let ensureReadyForFocus: () -> Void
    }

    private var hostedViews: [String: HostedPaneView] = [:]
    private var dividerViews: [String: PaneDividerView] = [:]

    /// Retained during a context menu interaction so actions can operate on the focused pane.
    private weak var contextMenuTab: WorkspaceTab?
    private weak var currentTab: WorkspaceTab?
    private var contextMenuCanClear = false
    private weak var lastContainerFrameTab: WorkspaceTab?
    private var lastContainerFrameSize: CGSize = .zero

    private var lastAppliedTheme: AppTheme = .tobacco
    private var currentCanvasMatte: NSColor = AppTheme.tobacco.canvasMatte
    private var currentPaneBackground: NSColor = AppTheme.tobacco.canvasBackground
    private var currentAccentColor: NSColor = AppTheme.tobacco.accentNSColor
    private var currentDividerColor: NSColor = AppTheme.tobacco.borderNSColor

    /// Keep panes visually contiguous; divider hit target can overlap content without adding a visible seam.
    private enum CanvasPaneChrome {
        static let interPaneGutter: CGFloat = 0
        static let outerInset: CGFloat = 0
        static let focusStripeHeight: CGFloat = 2
        static let focusStripeOpacity: Float = 0.9
    }

    private struct HorizontalDragState {
        let tree: ExternalTreeNode
        let firstNode: ExternalTreeNode
        let firstPaneIds: Set<String>
        let baselinePaneWidths: [String: CGFloat]
        let firstWidth: CGFloat
    }

    private struct TrailingEdgeDragState {
        let tree: ExternalTreeNode
        let targetNode: ExternalTreeNode
        let targetPaneIds: Set<String>
        let baselinePaneWidths: [String: CGFloat]
        let targetWidth: CGFloat
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
    private var trailingEdgeDragState: TrailingEdgeDragState?
    private var trailingResizeHandleView: PaneTrailingResizeHandleView?
    #if DEBUG
        private var dragTelemetryBySplitId: [String: DragTelemetry] = [:]
    #endif

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Manual frame defines canvas size for NSScrollView; avoid autoresizing that pins width to the clip view.
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = []
        layer?.backgroundColor = currentCanvasMatte.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Theme

    func applyTheme(_ theme: AppTheme) {
        lastAppliedTheme = theme
        currentAccentColor = theme.accentNSColor
        currentCanvasMatte = theme.canvasMatte
        currentPaneBackground = theme.canvasBackground
        currentDividerColor = theme.borderNSColor
        layer?.backgroundColor = theme.canvasMatte.cgColor

        for (_, hosted) in hostedViews {
            hosted.applyTheme(theme)
        }
        for (_, divider) in dividerViews {
            divider.accentColor = theme.accentNSColor
            divider.dividerColor = theme.borderNSColor
        }
        trailingResizeHandleView?.accentColor = theme.accentNSColor
    }

    // MARK: - Layout update

    /// Lays out terminal panes. Returns the focused pane’s frame in this document view’s coordinates (for scroll-to-visible).
    @discardableResult
    func update(tab: WorkspaceTab, viewportSize: CGSize) -> CGRect? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        currentTab = tab
        tab.rebalanceThreePaneHorizontalWidthsForStretchMode(viewportWidth: viewportSize.width)

        let canvasWidth = max(tab.canvasWidth <= 0 ? viewportSize.width : tab.canvasWidth, 1)
        let canvasHeight = viewportSize.height
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        frame = CGRect(origin: .zero, size: canvasSize)
        let containerSizeChanged =
            abs(lastContainerFrameSize.width - canvasSize.width) > 0.5
                || abs(lastContainerFrameSize.height - canvasSize.height) > 0.5
        if lastContainerFrameTab !== tab || containerSizeChanged {
            tab.bonsplitController.setContainerFrame(CGRect(origin: .zero, size: canvasSize))
            lastContainerFrameTab = tab
            lastContainerFrameSize = canvasSize
        }

        let tree = tab.bonsplitController.treeSnapshot()
        let snapshot = tab.bonsplitController.layoutSnapshot()
        let isMultiPane = snapshot.panes.count > 1

        let outerInset = CanvasPaneChrome.outerInset
        let innerLayoutRegion = CGRect(
            x: outerInset,
            y: outerInset,
            width: max(canvasWidth - 2 * outerInset, 1),
            height: max(canvasHeight - 2 * outerInset, 1)
        )

        // Partition the inner layout rect with the same rounded edges as `computeDividers`, so every
        // split gets exactly `interPaneGutter` (horizontal vs vertical splits stay visually consistent).
        let displayFrames: [String: CGRect] = if snapshot.panes.count <= 1, let only = snapshot.panes.first {
            [only.paneId: innerLayoutRegion]
        } else {
            paneFramesWithInterPaneGutters(
                from: tree,
                region: innerLayoutRegion,
                gutter: CanvasPaneChrome.interPaneGutter
            )
        }

        var activePaneIds = Set<String>()
        var focusedRect: CGRect?

        for pane in snapshot.panes {
            activePaneIds.insert(pane.paneId)
            guard let displayFrame = displayFrames[pane.paneId] else { continue }
            let isFocused = pane.paneId == snapshot.focusedPaneId
            guard let paneUUID = UUID(uuidString: pane.paneId) else { continue }
            let paneId = PaneID(id: paneUUID)

            guard let selectedTabIdStr = pane.selectedTabId,
                  let selectedTabUUID = UUID(uuidString: selectedTabIdStr)
            else { continue }

            let selectedTabId = TabID(uuid: selectedTabUUID)
            let contentKind = tab.paneContentKind(for: selectedTabUUID, fallbackPaneId: pane.paneId)
            let hosted: HostedPaneView
            switch contentKind {
            case .terminal:
                let surface = tab.surfaces[selectedTabUUID] ?? tab.createSurface(for: selectedTabId)

                if let existing = hostedViews[pane.paneId], existing.contentView === surface.hostedView {
                    hosted = existing
                } else {
                    hostedViews[pane.paneId]?.containerView.removeFromSuperview()
                    let hostedView = surface.hostedView
                    let containerView = FlippedContainerView(frame: displayFrame)
                    hostedView.setBackgroundColor(currentPaneBackground)
                    let paneIdStr = pane.paneId
                    hostedView.surfaceView.onFocused = { [weak tab] in
                        guard let tab, let paneUUID = UUID(uuidString: paneIdStr) else { return }
                        tab.bonsplitController.focusPane(PaneID(id: paneUUID))
                    }
                    hostedView.surfaceView.onContextMenu = { [weak self, weak tab] event in
                        guard let self, let tab else { return }
                        contextMenuTab = tab
                        contextMenuCanClear = true
                        NSMenu.popUpContextMenu(
                            buildContextMenu(
                                isMultiPane: isMultiPane,
                                canClear: true,
                                canMoveToNewTab: !(snapshot.panes.count == 1 && tab.isPinned)
                            ),
                            with: event,
                            for: self
                        )
                    }

                    hosted = HostedPaneView(
                        containerView: containerView,
                        contentView: hostedView,
                        focusView: hostedView.surfaceView,
                        kind: .terminal,
                        applyTheme: { theme in hostedView.setBackgroundColor(theme.canvasBackground) },
                        ensureReadyForFocus: {
                            if hostedView.surfaceView.terminalSurface?.surface == nil {
                                hostedView.surfaceView.terminalSurface?.attachToView(hostedView.surfaceView)
                            }
                        }
                    )
                    hostedViews[pane.paneId] = hosted
                    containerView.addSubview(hostedView)
                    addSubview(containerView)
                }

                // Deliver any pending input (e.g. clone command) once the surface exists.
                if let pending = tab.pendingInputOnceAttached, surface.surface != nil {
                    surface.sendText(pending)
                    tab.pendingInputOnceAttached = nil
                }
            case .browser:
                let surface =
                    tab.browserSurfaces[selectedTabUUID] ?? tab.createBrowserSurface(for: selectedTabId)

                if let existing = hostedViews[pane.paneId], existing.contentView === surface.hostedView {
                    hosted = existing
                } else {
                    hostedViews[pane.paneId]?.containerView.removeFromSuperview()
                    let hostedView = surface.hostedView
                    let containerView = FlippedContainerView(frame: displayFrame)
                    hostedView.setThemeBackground(currentPaneBackground)
                    let paneIdStr = pane.paneId
                    surface.onFocused = { [weak tab] in
                        guard let tab, let paneUUID = UUID(uuidString: paneIdStr) else { return }
                        tab.bonsplitController.focusPane(PaneID(id: paneUUID))
                    }
                    surface.onContextMenu = { [weak self, weak tab] event in
                        guard let self, let tab else { return }
                        contextMenuTab = tab
                        contextMenuCanClear = false
                        NSMenu.popUpContextMenu(
                            buildContextMenu(
                                isMultiPane: isMultiPane,
                                canClear: false,
                                canMoveToNewTab: !(snapshot.panes.count == 1 && tab.isPinned)
                            ),
                            with: event,
                            for: self
                        )
                    }
                    surface.onTitleChange = { [weak tab] title in
                        guard let tab else { return }
                        tab.bonsplitController.updateTab(selectedTabId, title: title)
                        NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
                    }
                    surface.onURLChange = { _ in
                        NotificationCenter.default.post(name: .workspacePersistenceNeeded, object: nil)
                    }
                    let shouldFocusAddressBar = tab.consumePendingBrowserAddressBarFocus(for: selectedTabUUID)

                    hosted = HostedPaneView(
                        containerView: containerView,
                        contentView: hostedView,
                        focusView: shouldFocusAddressBar
                            ? surface.addressBarFocusTargetView : surface.focusTargetView,
                        kind: .browser,
                        applyTheme: { theme in hostedView.setThemeBackground(theme.canvasBackground) },
                        ensureReadyForFocus: {}
                    )
                    hostedViews[pane.paneId] = hosted
                    containerView.addSubview(hostedView)
                    addSubview(containerView)
                }
            case .editor:
                let surface =
                    tab.editorSurfaces[selectedTabUUID] ?? tab.createEditorSurface(for: selectedTabId)

                if let existing = hostedViews[pane.paneId], existing.contentView === surface.hostedView {
                    hosted = existing
                } else {
                    hostedViews[pane.paneId]?.containerView.removeFromSuperview()
                    let hostedView = surface.hostedView
                    let containerView = FlippedContainerView(frame: displayFrame)
                    hostedView.wantsLayer = true
                    hostedView.layer?.backgroundColor = currentPaneBackground.cgColor
                    surface.applyAppTheme(lastAppliedTheme)
                    let paneIdStr = pane.paneId
                    surface.onFocused = { [weak tab] in
                        guard let tab, let paneUUID = UUID(uuidString: paneIdStr) else { return }
                        tab.bonsplitController.focusPane(PaneID(id: paneUUID))
                    }
                    surface.onContextMenu = { [weak self, weak tab] event in
                        guard let self, let tab else { return }
                        contextMenuTab = tab
                        contextMenuCanClear = false
                        NSMenu.popUpContextMenu(
                            buildContextMenu(
                                isMultiPane: isMultiPane,
                                canClear: false,
                                canMoveToNewTab: !(snapshot.panes.count == 1 && tab.isPinned)
                            ),
                            with: event,
                            for: self
                        )
                    }
                    surface.onOpenTerminalHere = { [weak tab] in
                        guard let tab else { return }
                        tab.replaceEditorPaneWithTerminal(
                            tabUUID: selectedTabUUID,
                            preferredRootPath: surface.rootPath
                        )
                    }
                    surface.onShowDiagnostics = { diagnostics in
                        let alert = NSAlert()
                        alert.messageText = "Editor Diagnostics"
                        alert.informativeText = diagnostics
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }

                    hosted = HostedPaneView(
                        containerView: containerView,
                        contentView: hostedView,
                        focusView: hostedView,
                        kind: .editor,
                        applyTheme: { theme in
                            hostedView.layer?.backgroundColor = theme.canvasBackground.cgColor
                            surface.applyAppTheme(theme)
                        },
                        ensureReadyForFocus: {
                            surface.ensureInitialized()
                        }
                    )
                    hostedViews[pane.paneId] = hosted
                    containerView.addSubview(hostedView)
                    addSubview(containerView)
                }
            }

            hosted.containerView.frame = displayFrame
            hosted.contentView.frame = CGRect(
                x: 0,
                y: 0,
                width: displayFrame.width,
                height: max(displayFrame.height, 1)
            )
            applyPaneChrome(to: hosted.containerView, focused: isFocused && isMultiPane)

            if isFocused {
                focusedRect = displayFrame
            }

            if hosted.kind == .editor,
               let editorSurface = tab.editorSurfaces[selectedTabUUID]
            {
                editorSurface.setFocused(isFocused)
            }
        }

        let removed = Set(hostedViews.keys).subtracting(activePaneIds)
        for paneId in removed {
            hostedViews[paneId]?.containerView.removeFromSuperview()
            hostedViews.removeValue(forKey: paneId)
        }

        let dividerDescriptors = computeDividers(from: tree, region: innerLayoutRegion)
        let activeSplitIds = Set(dividerDescriptors.map(\.splitId))

        for descriptor in dividerDescriptors {
            let dividerView: PaneDividerView
            if let existing = dividerViews[descriptor.splitId] {
                dividerView = existing
            } else {
                let created = PaneDividerView(frame: descriptor.frame)
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
                created.accentColor = currentAccentColor
                created.dividerColor = currentDividerColor
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

        if let trailingDescriptor = computeTrailingResizeDescriptor(
            from: tree,
            region: innerLayoutRegion
        ) {
            let handleView: PaneTrailingResizeHandleView
            if let existing = trailingResizeHandleView {
                handleView = existing
            } else {
                let created = PaneTrailingResizeHandleView(frame: trailingDescriptor.frame)
                created.accentColor = currentAccentColor
                created.onPressFocus = { [weak self] in
                    self?.focusPaneForTrailingResizeInteraction()
                }
                created.onDragBegan = { [weak self] in
                    self?.handleTrailingResizeDragBegan()
                }
                created.onDragDeltaPixels = { [weak self] deltaPixels in
                    self?.handleTrailingResizeDragDeltaPixels(deltaPixels)
                }
                created.onDragEnd = { [weak self] didDrag in
                    self?.handleTrailingResizeDragEnd(didDrag: didDrag)
                }
                trailingResizeHandleView = created
                handleView = created
                addSubview(handleView)
            }
            handleView.frame = trailingDescriptor.frame
            addSubview(handleView, positioned: .above, relativeTo: nil)
        } else {
            trailingResizeHandleView?.removeFromSuperview()
            trailingResizeHandleView = nil
            trailingEdgeDragState = nil
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

        syncFirstResponderWithFocusedPane(snapshot: snapshot)

        return focusedRect
    }

    /// Bonsplit tracks logical pane focus, but AppKit first responder may lag behind.
    /// After split / new tab / focus changes, keep keyboard input on the focused pane without stealing
    /// focus from sidebar or other UI outside this canvas.
    private func syncFirstResponderWithFocusedPane(snapshot: LayoutSnapshot) {
        guard let window, window.isKeyWindow else { return }
        guard let focusedPaneId = snapshot.focusedPaneId,
              let hosted = hostedViews[focusedPaneId]
        else { return }

        let target = hosted.focusView
        if window.firstResponder === target { return }

        if let view = window.firstResponder as? NSView,
           view.window === window,
           !view.isDescendant(of: self)
        {
            return
        }

        hosted.ensureReadyForFocus()
        window.makeFirstResponder(target)
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

    private struct TrailingResizeDescriptor {
        let frame: CGRect
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
        guard let split = HorizontalPaneSizingEngine.findSplit(in: tree, splitId: splitId) else {
            return
        }

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
        guard let split = HorizontalPaneSizingEngine.findSplit(in: tree, splitId: splitId) else {
            return
        }

        let branch: DividerBranch = (focusSide == .first) ? .first : .second
        let targetNode: ExternalTreeNode = (branch == .first) ? split.first : split.second
        let targetPaneIds = HorizontalPaneSizingEngine.paneIDs(in: targetNode)
        guard !targetPaneIds.isEmpty else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let targetPaneId: String? = if let focusedPaneId = snapshot.focusedPaneId, targetPaneIds.contains(focusedPaneId) {
            focusedPaneId
        } else {
            snapshot.panes.first(where: { targetPaneIds.contains($0.paneId) })?.paneId
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
              let state = horizontalDragStateBySplitId[splitId]
        else { return }

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
        guard tab.bonsplitController.setDividerPosition(newPosition, forSplit: splitUUID) else {
            return
        }
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
                        "divider.drag.metrics split=\(splitId.prefix(6)) samples=\(telemetry.sampleCount) "
                            + "elapsedMs=\(String(format: "%.1f", elapsed * 1000)) "
                            + "hz=\(String(format: "%.1f", hz)) maxGapMs=\(String(format: "%.1f", worstGapMs))"
                    )
                }
            #endif
        }

        currentTab?.notifyLayoutChanged()
    }

    private func focusPaneForTrailingResizeInteraction() {
        guard let tab = currentTab else { return }
        let tree = tab.bonsplitController.treeSnapshot()
        guard let targetNode = rightmostResizableNode(in: tree) else { return }
        let targetPaneIds = HorizontalPaneSizingEngine.paneIDs(in: targetNode)
        guard !targetPaneIds.isEmpty else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let targetPaneId: String? = if let focusedPaneId = snapshot.focusedPaneId, targetPaneIds.contains(focusedPaneId) {
            focusedPaneId
        } else {
            snapshot.panes.first(where: { targetPaneIds.contains($0.paneId) })?.paneId
                ?? targetPaneIds.sorted().last
        }

        guard let targetPaneId,
              let paneUUID = UUID(uuidString: targetPaneId)
        else { return }
        tab.bonsplitController.focusPane(PaneID(id: paneUUID))
    }

    private func handleTrailingResizeDragBegan() {
        guard let tab = currentTab else { return }
        let tree = tab.bonsplitController.treeSnapshot()
        guard let targetNode = rightmostResizableNode(in: tree) else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let paneWidths = HorizontalPaneSizingEngine.paneWidths(from: snapshot)
        let targetPaneIds = HorizontalPaneSizingEngine.paneIDs(in: targetNode)
        let targetWidth = subtreeWidth(for: targetNode, paneWidths: paneWidths)
        guard !targetPaneIds.isEmpty, targetWidth > 0 else { return }

        trailingEdgeDragState = TrailingEdgeDragState(
            tree: tree,
            targetNode: targetNode,
            targetPaneIds: targetPaneIds,
            baselinePaneWidths: paneWidths,
            targetWidth: targetWidth
        )
    }

    private func handleTrailingResizeDragDeltaPixels(_ deltaPixels: CGFloat) {
        guard let tab = currentTab,
              let state = trailingEdgeDragState
        else { return }

        let interactiveMinimum = tab.bonsplitController.configuration.appearance.minimumPaneWidth
        let minimumTargetWidth = HorizontalPaneSizingEngine.minimumRequiredWidth(
            for: state.targetNode,
            minimumPaneWidth: interactiveMinimum
        )

        let targetWidth = max(state.targetWidth + deltaPixels, minimumTargetWidth)
        guard state.targetWidth > 0 else { return }
        let scale = targetWidth / state.targetWidth

        var desiredPaneWidths = state.baselinePaneWidths
        for paneId in state.targetPaneIds {
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
    }

    private func handleTrailingResizeDragEnd(didDrag: Bool) {
        if didDrag {
            focusPaneForTrailingResizeInteraction()
        }
        trailingEdgeDragState = nil
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
        case let .pane(pane):
            return max(paneWidths[pane.id] ?? WorkspaceTab.interactiveMinimumPaneWidth, 1)
        case let .split(split):
            let first = subtreeWidth(for: split.first, paneWidths: paneWidths)
            let second = subtreeWidth(for: split.second, paneWidths: paneWidths)
            return split.orientation == "horizontal" ? (first + second) : max(first, second)
        }
    }

    /// Same split geometry as `computeDividers`, with a fixed physical gutter at each split (symmetric H/V).
    private func paneFramesWithInterPaneGutters(
        from node: ExternalTreeNode,
        region: CGRect,
        gutter: CGFloat
    ) -> [String: CGRect] {
        let half = gutter / 2
        switch node {
        case let .pane(p):
            return [p.id: region]
        case let .split(split):
            let axis: SplitAxis = split.orientation == "horizontal" ? .horizontal : .vertical
            let bounds = clampedDividerBounds(
                first: split.first,
                second: split.second,
                axis: axis,
                parentSpan: split.orientation == "horizontal" ? max(region.width, 1) : max(region.height, 1)
            )
            let position = CGFloat(split.dividerPosition).clamped(to: bounds)

            if split.orientation == "horizontal" {
                let dividerEdge = (region.minX + region.width * position).rounded()
                let firstRegion = CGRect(
                    x: region.minX,
                    y: region.minY,
                    width: max(dividerEdge - region.minX - half, 1),
                    height: region.height
                )
                let secondRegion = CGRect(
                    x: dividerEdge + half,
                    y: region.minY,
                    width: max(region.maxX - dividerEdge - half, 1),
                    height: region.height
                )
                return paneFramesWithInterPaneGutters(
                    from: split.first, region: firstRegion, gutter: gutter
                )
                .merging(
                    paneFramesWithInterPaneGutters(from: split.second, region: secondRegion, gutter: gutter),
                    uniquingKeysWith: { existing, _ in existing }
                )
            } else {
                let dividerEdge = (region.minY + region.height * position).rounded()
                let firstRegion = CGRect(
                    x: region.minX,
                    y: region.minY,
                    width: region.width,
                    height: max(dividerEdge - region.minY - half, 1)
                )
                let secondRegion = CGRect(
                    x: region.minX,
                    y: dividerEdge + half,
                    width: region.width,
                    height: max(region.maxY - dividerEdge - half, 1)
                )
                return paneFramesWithInterPaneGutters(
                    from: split.first, region: firstRegion, gutter: gutter
                )
                .merging(
                    paneFramesWithInterPaneGutters(from: split.second, region: secondRegion, gutter: gutter),
                    uniquingKeysWith: { existing, _ in existing }
                )
            }
        }
    }

    private func computeDividers(from node: ExternalTreeNode, region: CGRect) -> [DividerDescriptor] {
        switch node {
        case .pane:
            return []
        case let .split(split):
            let orientation: PaneDividerView.Orientation =
                split.orientation == "horizontal" ? .horizontal : .vertical
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

    private func computeTrailingResizeDescriptor(
        from node: ExternalTreeNode,
        region: CGRect
    ) -> TrailingResizeDescriptor? {
        guard rightmostResizableNode(in: node) != nil else { return nil }
        // Keep the full hit rect inside the document so the outer half is still hittable (NSView hit testing clips to bounds).
        let frame = CGRect(
            x: region.maxX - PaneTrailingResizeHandleView.hitThickness,
            y: region.minY,
            width: PaneTrailingResizeHandleView.hitThickness,
            height: region.height
        )
        return TrailingResizeDescriptor(frame: frame)
    }

    private func rightmostResizableNode(in node: ExternalTreeNode) -> ExternalTreeNode? {
        guard HorizontalPaneSizingEngine.containsHorizontalSplit(in: node) else { return nil }

        switch node {
        case .pane:
            return node
        case let .split(split):
            if split.orientation == "horizontal" {
                return rightmostResizableNode(in: split.second) ?? split.second
            }
            // Vertical stack occupies one shared column width, so resize the whole stack.
            return node
        }
    }

    private func clampedDividerBounds(
        first: ExternalTreeNode,
        second: ExternalTreeNode,
        axis: SplitAxis,
        parentSpan: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard parentSpan > 0 else { return 0 ... 1 }

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
            let midpoint = ((minPosition + maxPosition) / 2).clamped(to: 0 ... 1)
            minPosition = midpoint
            maxPosition = midpoint
        }
        return minPosition ... maxPosition
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
        case let .split(split):
            let first = minimumRequiredSize(for: split.first, axis: axis)
            let second = minimumRequiredSize(for: split.second, axis: axis)
            let matchesAxis =
                (axis == .horizontal && split.orientation == "horizontal")
                    || (axis == .vertical && split.orientation == "vertical")
            return matchesAxis ? (first + second) : max(first, second)
        }
    }

    private static let focusStripeLayerName = "termscape.focusStripe"

    private func applyPaneChrome(to view: NSView, focused: Bool) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.cornerRadius = 0
        layer.masksToBounds = true
        layer.borderWidth = 0
        updateFocusStripe(in: view, focused: focused)
    }

    private func updateFocusStripe(in view: NSView, focused: Bool) {
        guard let parentLayer = view.layer else { return }
        let existing = parentLayer.sublayers?.first { $0.name == Self.focusStripeLayerName }
        if focused {
            let stripe: CALayer
            if let existing { stripe = existing } else {
                let created = CALayer()
                created.name = Self.focusStripeLayerName
                created.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull(), "opacity": NSNull()]
                created.zPosition = 1000
                parentLayer.addSublayer(created)
                stripe = created
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stripe.backgroundColor = currentAccentColor.cgColor
            stripe.opacity = CanvasPaneChrome.focusStripeOpacity
            let width = parentLayer.bounds.width
            let height = CanvasPaneChrome.focusStripeHeight
            // Sublayers inherit the parent view's coordinate system: flipped views use y=0 at top; standard Quartz uses y=height-h at top.
            let y: CGFloat = view.isFlipped ? 0 : max(0, parentLayer.bounds.height - height)
            stripe.frame = CGRect(x: 0, y: y, width: width, height: height)
            CATransaction.commit()
        } else {
            existing?.removeFromSuperlayer()
        }
    }

    // MARK: - Context menu

    private func buildContextMenu(
        isMultiPane: Bool,
        canClear: Bool,
        canMoveToNewTab: Bool
    ) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        let newTerminalItem = makeItem(
            "New Terminal Tab",
            icon: "terminal",
            action: #selector(menuNewTab(_:))
        )
        newTerminalItem.keyEquivalent = "t"
        newTerminalItem.keyEquivalentModifierMask = .command
        menu.addItem(newTerminalItem)
        menu.addItem(
            makeItem("New Browser Tab", icon: "globe", action: #selector(menuNewBrowserTab(_:)))
        )
        menu.addItem(
            makeItem(
                "New Editor Tab",
                icon: "chevron.left.forwardslash.chevron.right",
                action: #selector(menuNewEditorTab(_:))
            )
        )
        menu.addItem(.separator())

        let splitRightItem = makeItem(
            "Split Terminal Right",
            icon: "rectangle.split.2x1",
            action: #selector(menuSplitRight(_:))
        )
        splitRightItem.keyEquivalent = "d"
        splitRightItem.keyEquivalentModifierMask = .command
        menu.addItem(splitRightItem)
        let splitDownItem = makeItem(
            "Split Terminal Down",
            icon: "rectangle.split.1x2",
            action: #selector(menuSplitDown(_:))
        )
        splitDownItem.keyEquivalent = "d"
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(splitDownItem)
        menu.addItem(.separator())
        menu.addItem(
            makeItem(
                "Split Browser Right",
                icon: "globe",
                action: #selector(menuSplitBrowserRight(_:))
            )
        )
        menu.addItem(
            makeItem(
                "Split Browser Down",
                icon: "globe",
                action: #selector(menuSplitBrowserDown(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            makeItem(
                "Split Editor Right",
                icon: "chevron.left.forwardslash.chevron.right",
                action: #selector(menuSplitEditorRight(_:))
            )
        )
        menu.addItem(
            makeItem(
                "Split Editor Down",
                icon: "chevron.left.forwardslash.chevron.right",
                action: #selector(menuSplitEditorDown(_:))
            )
        )

        menu.addItem(.separator())
        let moveToNewTabItem = makeItem(
            "Move to New Tab",
            icon: "arrow.up.right.square",
            action: #selector(menuMoveToNewTab(_:))
        )
        moveToNewTabItem.isEnabled = canMoveToNewTab
        menu.addItem(moveToNewTabItem)
        menu.addItem(.separator())

        let clearItem = makeItem("Clear", icon: "eraser.fill", action: #selector(menuClear(_:)))
        clearItem.keyEquivalent = "k"
        clearItem.keyEquivalentModifierMask = .command
        clearItem.isEnabled = canClear
        menu.addItem(clearItem)
        let closeTitle = isMultiPane ? "Close Pane" : "Close Tab"
        let closeItem = makeItem(closeTitle, icon: "xmark", action: #selector(menuClose(_:)))
        closeItem.keyEquivalent = "w"
        closeItem.keyEquivalentModifierMask = .command
        menu.addItem(closeItem)

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

    @objc private func menuSplitRight(_: Any?) {
        NotificationCenter.default.post(name: .splitRight, object: nil)
    }

    @objc private func menuSplitDown(_: Any?) {
        NotificationCenter.default.post(name: .splitDown, object: nil)
    }

    @objc private func menuSplitBrowserRight(_: Any?) {
        NotificationCenter.default.post(name: .splitBrowserRight, object: nil)
    }

    @objc private func menuSplitBrowserDown(_: Any?) {
        NotificationCenter.default.post(name: .splitBrowserDown, object: nil)
    }

    @objc private func menuSplitEditorRight(_: Any?) {
        NotificationCenter.default.post(name: .splitEditorRight, object: nil)
    }

    @objc private func menuSplitEditorDown(_: Any?) {
        NotificationCenter.default.post(name: .splitEditorDown, object: nil)
    }

    @objc private func menuNewTab(_: Any?) {
        NotificationCenter.default.post(name: .newTab, object: nil)
    }

    @objc private func menuNewBrowserTab(_: Any?) {
        NotificationCenter.default.post(name: .newBrowserTab, object: nil)
    }

    @objc private func menuNewEditorTab(_: Any?) {
        guard let tab = currentTab else { return }
        let snapshot = tab.bonsplitController.layoutSnapshot()
        let root = tab.resolveEditorRootFromFocusedContext(
            targetPaneId: tab.bonsplitController.focusedPaneId,
            snapshot: snapshot
        )
        let pathKey = Notification.Name.MoveToNewTabKey.editorRootPath
        NotificationCenter.default.post(
            name: .newEditorTab,
            object: nil,
            userInfo: [pathKey: root]
        )
    }

    @objc private func menuMoveToNewTab(_: Any?) {
        guard let tab = contextMenuTab else { return }
        let isSinglePane = tab.bonsplitController.allPaneIds.count == 1
        guard !(isSinglePane && tab.isPinned) else { return }

        let snapshot = tab.bonsplitController.layoutSnapshot()
        guard let focusedPaneId = snapshot.focusedPaneId,
              let pane = snapshot.panes.first(where: { $0.paneId == focusedPaneId }),
              let selectedTabId = pane.selectedTabId,
              let tabUUID = UUID(uuidString: selectedTabId)
        else { return }

        let kind = tab.paneContentKind(for: tabUUID, fallbackPaneId: focusedPaneId)
        let key = Notification.Name.MoveToNewTabKey.self
        let userInfo: [String: Any]
        switch kind {
        case .terminal:
            guard let surface = tab.detachTerminalSurface(for: tabUUID) else { return }
            userInfo = [
                key.surface: surface,
                key.sourceTab: tab,
                key.contentKind: kind.rawValue,
            ]
        case .browser:
            guard let surface = tab.detachBrowserSurface(for: tabUUID) else { return }
            userInfo = [
                key.browserSurface: surface,
                key.sourceTab: tab,
                key.contentKind: kind.rawValue,
            ]
        case .editor:
            guard let rootPath = tab.editorRootPath(for: tabUUID) else { return }
            if let surface = tab.detachEditorSurface(for: tabUUID) {
                userInfo = [
                    key.editorSurface: surface,
                    key.sourceTab: tab,
                    key.contentKind: kind.rawValue,
                ]
            } else {
                userInfo = [
                    key.editorRootPath: rootPath,
                    key.sourceTab: tab,
                    key.contentKind: kind.rawValue,
                ]
            }
        }

        // Close the source pane if it's not the only one.
        // (For single-pane, the workspace tab itself is closed by the notification handler.)
        if !isSinglePane, let paneUUID = UUID(uuidString: focusedPaneId) {
            tab.bonsplitController.closePane(PaneID(id: paneUUID))
        }

        var payload = userInfo
        payload[key.closeSourceTab] = isSinglePane
        NotificationCenter.default.post(name: .moveToNewTab, object: nil, userInfo: payload)
    }

    @objc private func menuClose(_: Any?) {
        NotificationCenter.default.post(name: .closeTab, object: nil)
    }

    @objc private func menuClear(_: Any?) {
        guard contextMenuCanClear else { return }
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

@MainActor
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool {
        true
    }
}

/// Invisible trailing-edge hit target that resizes the rightmost pane column width.
@MainActor
private final class PaneTrailingResizeHandleView: NSView {
    static let hitThickness: CGFloat = 10

    var accentColor: NSColor {
        get { grabber.accentColor }
        set { grabber.accentColor = newValue }
    }

    var onPressFocus: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragDeltaPixels: ((CGFloat) -> Void)?
    var onDragEnd: ((Bool) -> Void)?

    private var isTrackingPointer = false
    private var dragStartPointInParent: CGPoint?
    private var hasDragMovement = false

    private let grabber = PaneGrabberIndicator()
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        grabber.longAxis = .vertical
        grabber.attach(to: self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var frame: NSRect {
        didSet { grabber.updateFrame(in: bounds) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        isHovering = true
        updateGrabber()
    }

    override func mouseExited(with _: NSEvent) {
        isHovering = false
        updateGrabber()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        isTrackingPointer = true
        dragStartPointInParent = dragPoint(inParentFor: event)
        hasDragMovement = false
        onPressFocus?()
        updateGrabber()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPointer else { return }
        guard let startPoint = dragStartPointInParent else { return }
        let currentPoint = dragPoint(inParentFor: event)
        let deltaPixels = currentPoint.x - startPoint.x
        if !hasDragMovement, abs(deltaPixels) >= 1 {
            hasDragMovement = true
            onDragBegan?()
        }
        onDragDeltaPixels?(deltaPixels)
    }

    override func mouseUp(with _: NSEvent) {
        finishDragging()
    }

    private func finishDragging() {
        guard isTrackingPointer else { return }
        isTrackingPointer = false
        dragStartPointInParent = nil
        onDragEnd?(hasDragMovement)
        updateGrabber()
    }

    private func dragPoint(inParentFor event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return superview?.convert(localPoint, from: self) ?? localPoint
    }

    private func updateGrabber() {
        grabber.apply(isHovering: isHovering, isTracking: isTrackingPointer, in: bounds)
    }
}
