import AppKit
import SwiftUI

/// Invisible region that drags the host window on mouse-down and performs the
/// standard title-bar double-click action (zoom/minimize per system prefs).
///
/// The app keeps `window.isMovable = false` globally so SwiftUI content never
/// steals unexpected drags; this view temporarily flips it on for `performDrag`.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DragView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only claim hits during a mouse-down so hover / tracking in sibling
            // views is unaffected.
            guard bounds.contains(point),
                  NSApp.currentEvent?.type == .leftMouseDown
            else { return nil }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else {
                super.mouseDown(with: event)
                return
            }

            if event.clickCount >= 2 {
                performStandardDoubleClick(on: window)
                return
            }

            let previousMovable = window.isMovable
            window.isMovable = true
            defer { window.isMovable = previousMovable }

            window.performDrag(with: event)
        }

        private func performStandardDoubleClick(on window: NSWindow) {
            let defaults = UserDefaults.standard
                .persistentDomain(forName: UserDefaults.globalDomain) ?? [:]

            if let action = (defaults["AppleActionOnDoubleClick"] as? String)?
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            {
                switch action {
                case "minimize":
                    window.miniaturize(nil)
                    return
                case "none":
                    return
                case "maximize", "zoom":
                    window.zoom(nil)
                    return
                default:
                    break
                }
            }

            if let miniaturize = defaults["AppleMiniaturizeOnDoubleClick"] as? Bool, miniaturize {
                window.miniaturize(nil)
                return
            }

            window.zoom(nil)
        }
    }
}
