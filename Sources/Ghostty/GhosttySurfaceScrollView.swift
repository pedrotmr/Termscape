import AppKit

/// Simple container NSView that wraps a GhosttyNSView.
/// Handles background color and acts as the hosted view placed into the canvas.
final class GhosttySurfaceScrollView: NSView {
    private let backgroundView: NSView
    private let scrollView: NSScrollView
    let surfaceView: GhosttyNSView

    init(surfaceView: GhosttyNSView) {
        self.surfaceView = surfaceView
        backgroundView = NSView()
        scrollView = NSScrollView()

        super.init(frame: .zero)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupLayout() {
        wantsLayer = true

        // Background
        backgroundView.wantsLayer = true
        // Replaced on embed via `setBackgroundColor` from the active `AppTheme`.
        backgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        // ScrollView for the terminal (handles terminal internal scrollback)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Surface view is the document view of the scroll view
        scrollView.documentView = surfaceView
        surfaceView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setBackgroundColor(_ color: NSColor) {
        backgroundView.layer?.backgroundColor = color.cgColor
    }

    override func layout() {
        super.layout()
        // Keep surface view sized to scroll view content area
        let contentSize = scrollView.contentView.bounds.size
        if contentSize.width > 0, contentSize.height > 0 {
            surfaceView.frame = CGRect(origin: .zero, size: contentSize)
        }
    }

    func cancelFocusRequest() {}
}
