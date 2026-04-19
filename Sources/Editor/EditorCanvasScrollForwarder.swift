import AppKit

/// Routes horizontal trackpad / Shift+vertical wheel on editor panes: chrome → workspace canvas;
/// the code `NSScrollView` keeps horizontal deltas when the document is wider than the viewport.
@MainActor
enum EditorCanvasScrollForwarder {
    private final class WeakBox {
        weak var view: NSView?
        init(_ view: NSView) {
            self.view = view
        }
    }

    private static var tracked: [WeakBox] = []
    private static var monitor: Any?

    static func track(_ hostingView: NSView) {
        tracked.append(WeakBox(hostingView))
        installMonitorIfNeeded()
    }

    static func untrack(_ hostingView: NSView) {
        tracked.removeAll { $0.view === hostingView || $0.view == nil }
        removeMonitorIfIdle()
    }

    private static func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                handleScrollEvent(event)
            }
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
        guard !tracked.isEmpty else {
            removeMonitorIfIdle()
            return event
        }

        let locationInWindow = event.locationInWindow

        for box in tracked {
            guard let host = box.view, host.window === window else { continue }
            let pointInHost = host.convert(locationInWindow, from: nil)
            guard host.bounds.contains(pointInHost) else { continue }

            guard let canvas = host.enclosingTermscapeCanvasScrollView(),
                  canvas.documentCanvasView.frame.width > canvas.documentVisibleRect.width + 0.5
            else { continue }

            if horizontalScrollViewClaimingWheel(at: locationInWindow, in: host) != nil {
                return event
            }

            canvas.applyHorizontalScrollDelta(-panDelta)
            return nil
        }

        return event
    }

    /// First `NSScrollView` in the hit-test chain under `host` whose document is wider than the clip (code area, tab strip, breadcrumbs, etc.).
    private static func horizontalScrollViewClaimingWheel(at locationInWindow: CGPoint, in host: NSView) -> NSScrollView? {
        let p = host.convert(locationInWindow, from: nil)
        guard host.bounds.contains(p) else { return nil }
        var view: NSView? = host.hitTest(p)
        while let v = view, v !== host {
            if let scroll = v as? NSScrollView, scrollViewWantsHorizontalWheel(scroll) {
                return scroll
            }
            view = v.superview
        }
        return nil
    }

    private static func scrollViewWantsHorizontalWheel(_ scroll: NSScrollView) -> Bool {
        let docW = scroll.documentView?.bounds.width ?? 0
        let visibleW = scroll.contentView.bounds.width
        return docW > visibleW + 0.5
    }
}
