import AppKit

/// Routes horizontal trackpad / Shift+vertical wheel on editor panes: chrome → workspace canvas;
/// the code `NSScrollView` keeps horizontal deltas when the document is wider than the viewport.
enum EditorCanvasScrollForwarder {
    private static let codeScrollIdentifier = NSUserInterfaceItemIdentifier("termscape.editor.sourceScrollView")

    static func tagCodeScrollView(_ scroll: NSScrollView) {
        scroll.identifier = codeScrollIdentifier
    }

    private final class WeakBox {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private static var tracked: [WeakBox] = []
    private static var monitor: Any?

    static func track(_ hostingView: NSView) {
        assert(Thread.isMainThread)
        tracked.append(WeakBox(hostingView))
        installMonitorIfNeeded()
    }

    static func untrack(_ hostingView: NSView) {
        assert(Thread.isMainThread)
        tracked.removeAll { $0.view === hostingView || $0.view == nil }
        removeMonitorIfIdle()
    }

    private static func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleScrollEvent(event)
        }
    }

    private static func removeMonitorIfIdle() {
        compactTracked()
        guard tracked.isEmpty, let m = monitor else { return }
        NSEvent.removeMonitor(m)
        monitor = nil
    }

    private static func compactTracked() {
        tracked.removeAll { $0.view == nil }
    }

    private static func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window else { return event }

        guard let panDelta = event.termscape_workspaceHorizontalPanScrollingDelta() else { return event }

        compactTracked()
        guard !tracked.isEmpty else { return event }

        let locationInWindow = event.locationInWindow

        for box in tracked {
            guard let host = box.view, host.window === window else { continue }
            let pointInHost = host.convert(locationInWindow, from: nil)
            guard host.bounds.contains(pointInHost) else { continue }

            guard let canvas = host.enclosingTermscapeCanvasScrollView(),
                  canvas.documentCanvasView.frame.width > canvas.documentVisibleRect.width + 0.5
            else { continue }

            if let codeScroll = findTaggedCodeScrollView(in: host) {
                let ptInCode = codeScroll.convert(locationInWindow, from: nil)
                if codeScroll.bounds.contains(ptInCode) {
                    let docWidth = codeScroll.documentView?.bounds.width ?? 0
                    let visibleW = codeScroll.contentView.bounds.width
                    let editorNeedsHorizontal = docWidth > visibleW + 0.5
                    if editorNeedsHorizontal {
                        return event
                    }
                }
            }

            canvas.applyHorizontalScrollDelta(-panDelta)
            return nil
        }

        return event
    }

    private static func findTaggedCodeScrollView(in root: NSView) -> NSScrollView? {
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            if let scroll = v as? NSScrollView, scroll.identifier == codeScrollIdentifier {
                return scroll
            }
            stack.append(contentsOf: v.subviews)
        }
        return nil
    }
}
