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
        hasVerticalScroller = false
        horizontalScrollElasticity = .automatic
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

        let docWidth = documentCanvasView.frame.width
        let visWidth = documentVisibleRect.width
        let horizontalOverflow = docWidth > visWidth + 0.5

        // Keep the horizontal scroller visible when content is wider than the viewport.
        autohidesScrollers = !horizontalOverflow
        if horizontalOverflow {
            horizontalScroller?.isHidden = false
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
        let needsScroll = focusRect.minX < visible.minX + margin || focusRect.maxX > visible.maxX - margin
        guard needsScroll else { return }
        _ = contentView.scrollToVisible(focusRect.insetBy(dx: -margin, dy: -margin))
        reflectScrolledClipView(contentView)
    }

    func applyTheme(canvasBackground: NSColor, accentColor: NSColor) {
        documentCanvasView.applyTheme(canvasBackground: canvasBackground, accentColor: accentColor)
    }

    // MARK: - Coalesced layout

    private var needsCoalescedLayout = false

    override func layout() {
        super.layout()
        scheduleCoalescedLayout()
    }

    /// Coalesces rapid layout() calls (e.g. during window resize) into a single update.
    private func scheduleCoalescedLayout() {
        guard !needsCoalescedLayout else { return }
        needsCoalescedLayout = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.needsCoalescedLayout else { return }
            self.needsCoalescedLayout = false
            if let tab = self.hostedTab {
                self.updateLayout(for: tab, options: [])
            }
        }
    }
}
