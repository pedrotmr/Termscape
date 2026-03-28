import AppKit

/// The horizontal-scrolling canvas that holds all terminal panes.
/// Key behavior: panes have a minimum width and the canvas scrolls horizontally
/// instead of squeezing panes below their minimum width.
final class CanvasScrollView: NSScrollView {
    let documentCanvasView: CanvasDocumentView

    override init(frame frameRect: NSRect) {
        documentCanvasView = CanvasDocumentView()
        super.init(frame: frameRect)
        setupScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupScrollView() {
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder

        documentView = documentCanvasView
    }

    func updateLayout(for tab: WorkspaceTab) {
        let viewportSize = contentView.bounds.size
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }
        documentCanvasView.update(tab: tab, viewportSize: viewportSize)
    }

    override func layout() {
        super.layout()
        // Trigger relayout when the scroll view resizes
        if let window, !window.inLiveResize {
            // Will be triggered by the hosting view's updateNSView
        }
    }
}
