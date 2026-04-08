import AppKit
import Bonsplit

/// NSView that positions terminal surface views absolutely based on the Bonsplit layout.
final class CanvasDocumentView: NSView {
    private var hostedViews: [String: GhosttySurfaceScrollView] = [:]
    private let layoutEngine = PaneLayoutEngine()
    /// Retained during a context menu interaction so the Clear action can reach the focused surface.
    private weak var contextMenuTab: WorkspaceTab?
    private var currentAccentColor: NSColor = NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Manual frame defines canvas size for NSScrollView; avoid autoresizing that pins width to the clip view.
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = []
        // Default to tobacco theme canvas bg; overwritten via applyTheme on first render
        layer?.backgroundColor = NSColor(red: 0.125, green: 0.118, blue: 0.110, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Theme

    func applyTheme(canvasBackground: NSColor, accentColor: NSColor) {
        layer?.backgroundColor = canvasBackground.cgColor
        currentAccentColor = accentColor
        // Re-apply borders with new accent color
        for (_, view) in hostedViews {
            let isFocused = view.layer?.borderWidth == 1.5
            if isFocused {
                view.layer?.borderColor = accentColor.withAlphaComponent(0.85).cgColor
            }
        }
    }

    // MARK: - Layout update

    /// Lays out terminal panes. Returns the focused pane’s frame in this document view’s coordinates (for scroll-to-visible).
    @discardableResult
    func update(tab: WorkspaceTab, viewportSize: CGSize) -> CGRect? {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }

        let tree = tab.bonsplitController.treeSnapshot()
        let layout = layoutEngine.computeLayout(from: tree, viewportWidth: viewportSize.width)
        let canvasSize = CGSize(width: layout.canvasWidth, height: viewportSize.height)

        frame = CGRect(origin: .zero, size: canvasSize)
        tab.bonsplitController.setContainerFrame(CGRect(origin: .zero, size: canvasSize))

        let snapshot = tab.bonsplitController.layoutSnapshot()
        let isMultiPane = snapshot.panes.count > 1
        let columnWidth = layout.canvasWidth / max(CGFloat(layout.columnCount), 1)

        var activePaneIds = Set<String>()
        var focusedRect: CGRect?

        for pane in snapshot.panes {
            activePaneIds.insert(pane.paneId)

            let rawFrame: CGRect
            if let span = layout.columnSpans[pane.paneId] {
                let x = CGFloat(span.colStart) * columnWidth
                let w = CGFloat(span.colSpan) * columnWidth
                rawFrame = CGRect(
                    x: x,
                    y: pane.frame.y,
                    width: w,
                    height: pane.frame.height
                )
            } else {
                rawFrame = CGRect(
                    x: pane.frame.x,
                    y: pane.frame.y,
                    width: pane.frame.width,
                    height: pane.frame.height
                )
            }

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

            hostedView.frame = rawFrame
            applyBorder(to: hostedView, focused: isFocused, multiPane: isMultiPane)

            // Deliver any pending input (e.g. clone command) once the surface exists.
            if let pending = tab.pendingInputOnceAttached, surface.surface != nil {
                surface.sendText(pending)
                tab.pendingInputOnceAttached = nil
            }

            if isFocused {
                focusedRect = rawFrame
            }
        }

        let removed = Set(hostedViews.keys).subtracting(activePaneIds)
        for paneId in removed {
            hostedViews[paneId]?.removeFromSuperview()
            hostedViews.removeValue(forKey: paneId)
        }

        return focusedRect
    }

    // MARK: - Helpers

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
