import AppKit

/// Options for `CanvasScrollView.updateLayout(for:options:)`.
struct CanvasLayoutUpdateOptions: OptionSet {
    let rawValue: Int
    /// After layout, scroll the minimal amount so the focused pane is visible (e.g. after splitting right).
    static let scrollFocusedPaneIntoView = CanvasLayoutUpdateOptions(rawValue: 1 << 0)
}

/// The horizontal-scrolling canvas that holds all terminal panes.
final class CanvasScrollView: NSScrollView {
    let documentCanvasView: CanvasDocumentView

    /// Weak so the scroll view does not retain the tab; updated from `CanvasHostingView`.
    weak var hostedTab: WorkspaceTab?

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
        hasVerticalScroller = true
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .automatic
        scrollerStyle = .legacy
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        documentView = documentCanvasView
    }

    func updateLayout(for tab: WorkspaceTab, options: CanvasLayoutUpdateOptions = []) {
        let viewportSize = documentVisibleRect.size
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }

        let focusRect = documentCanvasView.update(tab: tab, viewportSize: viewportSize)

        let docSize = documentCanvasView.frame.size
        let visSize = documentVisibleRect.size
        let horizontalOverflow = docSize.width > visSize.width + 0.5
        let verticalOverflow = docSize.height > visSize.height + 0.5
        let anyOverflow = horizontalOverflow || verticalOverflow

        // Keep scrollers visible when content exceeds the viewport in either axis.
        autohidesScrollers = !anyOverflow
        if horizontalOverflow {
            horizontalScroller?.isHidden = false
        }
        if verticalOverflow {
            verticalScroller?.isHidden = false
        }

        tile()
        reflectScrolledClipView(contentView)

        if options.contains(.scrollFocusedPaneIntoView), let rect = focusRect {
            scrollFocusedPaneIfNeeded(focusRect: rect)
        }
    }

    /// Called from terminal views when horizontal scroll should move the canvas (trackpad / Shift+scroll).
    func applyHorizontalScrollDelta(_ deltaX: CGFloat) {
        let docWidth = documentCanvasView.frame.width
        let visWidth = documentVisibleRect.width
        let maxOriginX = max(0, docWidth - visWidth)
        guard maxOriginX > 0 else { return }

        var b = contentView.bounds
        b.origin.x += deltaX
        b.origin.x = min(max(0, b.origin.x), maxOriginX)
        contentView.bounds = b
        reflectScrolledClipView(contentView)
    }

    private func scrollFocusedPaneIfNeeded(focusRect: CGRect) {
        let visible = documentVisibleRect
        let margin: CGFloat = 16
        let needsH = focusRect.minX < visible.minX + margin || focusRect.maxX > visible.maxX - margin
        let needsV = focusRect.minY < visible.minY + margin || focusRect.maxY > visible.maxY - margin
        guard needsH || needsV else { return }
        _ = contentView.scrollToVisible(focusRect.insetBy(dx: -margin, dy: -margin))
        reflectScrolledClipView(contentView)
    }

    func applyTheme(canvasBackground: NSColor, accentColor: NSColor) {
        documentCanvasView.applyTheme(canvasBackground: canvasBackground, accentColor: accentColor)
    }

    override func layout() {
        super.layout()
        if let tab = hostedTab {
            updateLayout(for: tab, options: [])
        }
    }
}
