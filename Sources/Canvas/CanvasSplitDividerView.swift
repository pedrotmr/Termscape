import AppKit
import Bonsplit

/// Draggable splitter between panes; updates Bonsplit divider ratios for the canvas layout.
final class CanvasSplitDividerView: NSView {
    weak var tab: WorkspaceTab?

    private(set) var splitId: UUID?
    private(set) var splitOrientation: SplitOrientation?
    /// Region in document coordinates that this split occupies (both children).
    private(set) var splitRegion: CGRect = .zero

    private var minPaneWidth: CGFloat = 600
    private var minPaneHeight: CGFloat = 200

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        splitId: UUID,
        orientation: SplitOrientation,
        region: CGRect,
        minPaneWidth: CGFloat,
        minPaneHeight: CGFloat,
        tab: WorkspaceTab
    ) {
        self.splitId = splitId
        self.splitOrientation = orientation
        self.splitRegion = region
        self.minPaneWidth = minPaneWidth
        self.minPaneHeight = minPaneHeight
        self.tab = tab
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        switch splitOrientation {
        case .horizontal:
            addCursorRect(bounds, cursor: .resizeLeftRight)
        case .vertical:
            addCursorRect(bounds, cursor: .resizeUpDown)
        case .none:
            break
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.disableCursorRects()
    }

    override func mouseUp(with event: NSEvent) {
        window?.enableCursorRects()
        relayout()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tab, let splitId, let orientation = splitOrientation,
              let doc = superview as? CanvasDocumentView else { return }
        let locInDoc = doc.convert(event.locationInWindow, from: nil)

        let w = max(splitRegion.width, 1)
        let h = max(splitRegion.height, 1)

        switch orientation {
        case .horizontal:
            let minRatio = max(0.1, minPaneWidth / w)
            let maxRatio = min(0.9, 1 - minPaneWidth / w)
            guard maxRatio > minRatio else { return }
            var ratio = (locInDoc.x - splitRegion.minX) / w
            ratio = min(max(ratio, minRatio), maxRatio)
            tab.bonsplitController.setDividerPosition(ratio, forSplit: splitId, fromExternal: true)
        case .vertical:
            let minRatio = max(0.1, minPaneHeight / h)
            let maxRatio = min(0.9, 1 - minPaneHeight / h)
            guard maxRatio > minRatio else { return }
            var ratio = (locInDoc.y - splitRegion.minY) / h
            ratio = min(max(ratio, minRatio), maxRatio)
            tab.bonsplitController.setDividerPosition(ratio, forSplit: splitId, fromExternal: true)
        }

        relayout()
    }

    private func relayout() {
        guard let tab else { return }
        var v: NSView? = superview
        while let cur = v {
            if let scroll = cur as? CanvasScrollView {
                scroll.updateLayout(for: tab, options: [])
                return
            }
            v = cur.superview
        }
    }
}
