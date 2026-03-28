import AppKit
import Bonsplit

/// NSView that positions terminal surface views absolutely based on the Bonsplit layout.
/// This is the document view of CanvasScrollView.
final class CanvasDocumentView: NSView {
    private var hostedViews: [String: GhosttySurfaceScrollView] = [:] // paneId → view
    private let layoutEngine = PaneLayoutEngine()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Background shows through the 1px gaps between panes (acts as divider color)
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout update

    func update(tab: WorkspaceTab, viewportSize: CGSize) {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }

        let tree = tab.bonsplitController.treeSnapshot()

        // Compute canvas width (may be wider than viewport for horizontal scroll)
        let canvasWidth = layoutEngine.requiredCanvasWidth(for: tree, viewportWidth: viewportSize.width)
        let canvasSize = CGSize(width: canvasWidth, height: viewportSize.height)

        // Update canvas frame
        frame = CGRect(origin: .zero, size: canvasSize)

        // Tell Bonsplit the container size so it computes correct pixel frames
        tab.bonsplitController.setContainerFrame(CGRect(origin: .zero, size: canvasSize))

        // Get pixel frames from Bonsplit
        let snapshot = tab.bonsplitController.layoutSnapshot()

        let isMultiPane = snapshot.panes.count > 1

        // Track which panes are active
        var activePaneIds = Set<String>()

        for pane in snapshot.panes {
            activePaneIds.insert(pane.paneId)

            let rawFrame = CGRect(
                x: pane.frame.x,
                y: pane.frame.y,
                width: pane.frame.width,
                height: pane.frame.height
            )

            // Use Bonsplit's frames as-is; the 0.5pt border on each pane creates
            // a clean ~1pt visual separator at shared edges without any extra gap.
            let frame = rawFrame
            let isFocused = pane.paneId == snapshot.focusedPaneId

            // Find or create the surface view for this pane
            guard let selectedTabIdStr = pane.selectedTabId,
                  let selectedTabUUID = UUID(uuidString: selectedTabIdStr) else {
                // New empty pane (just split, tab not yet created) — skip
                continue
            }

            let surface: TerminalSurface
            if let existing = tab.surfaces[selectedTabUUID] {
                surface = existing
            } else {
                // Surface not yet created for this pane's tab — create it now
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
            }

            hostedView.frame = frame

            // Pane border: subtle for all panes, accent-colored for focused pane
            applyBorder(to: hostedView, focused: isFocused, multiPane: isMultiPane)

            // Wire focus callback — clicking this terminal tells Bonsplit which pane is active
            let paneIdStr = pane.paneId
            hostedView.surfaceView.onFocused = { [weak tab] in
                guard let tab, let paneUUID = UUID(uuidString: paneIdStr) else { return }
                tab.bonsplitController.focusPane(PaneID(id: paneUUID))
            }
        }

        // Remove views for panes that no longer exist
        let removed = Set(hostedViews.keys).subtracting(activePaneIds)
        for paneId in removed {
            hostedViews[paneId]?.removeFromSuperview()
            hostedViews.removeValue(forKey: paneId)
        }
    }

    // MARK: - Helpers

    /// Returns a frame inset only on interior edges (edges shared with other panes),
    /// leaving outer edges flush with the canvas boundary.
    private func interiorInsetFrame(_ frame: CGRect, canvasSize: CGSize, inset: CGFloat) -> CGRect {
        guard inset > 0 else { return frame }

        let left   = frame.minX > 0.5         ? frame.minX + inset : frame.minX
        let top    = frame.minY > 0.5         ? frame.minY + inset : frame.minY
        let right  = frame.maxX < canvasSize.width  - 0.5 ? frame.maxX - inset : frame.maxX
        let bottom = frame.maxY < canvasSize.height - 0.5 ? frame.maxY - inset : frame.maxY

        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
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
            view.layer?.borderColor = NSColor(red: 0.337, green: 0.400, blue: 0.957, alpha: 0.85).cgColor
        } else {
            view.layer?.borderWidth = 0.5
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        }
    }
}
