import AppKit
import SwiftUI

private enum WindowDragSuppressionKey {
    static var depth = "termscape.windowDragSuppressionDepth"
}

func beginWindowDragSuppression(window: NSWindow?) -> Int {
    guard let window else { return 0 }
    let current = windowDragSuppressionDepth(window: window)
    let next = current + 1
    objc_setAssociatedObject(
        window,
        &WindowDragSuppressionKey.depth,
        NSNumber(value: next),
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    return next
}

@discardableResult
func endWindowDragSuppression(window: NSWindow?) -> Int {
    guard let window else { return 0 }
    let current = windowDragSuppressionDepth(window: window)
    let next = max(current - 1, 0)

    if next == 0 {
        objc_setAssociatedObject(
            window,
            &WindowDragSuppressionKey.depth,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    } else {
        objc_setAssociatedObject(
            window,
            &WindowDragSuppressionKey.depth,
            NSNumber(value: next),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    return next
}

func windowDragSuppressionDepth(window: NSWindow?) -> Int {
    guard let window,
          let value = objc_getAssociatedObject(window, &WindowDragSuppressionKey.depth) as? NSNumber
    else { return 0 }
    return value.intValue
}

func isWindowDragSuppressed(window: NSWindow?) -> Bool {
    windowDragSuppressionDepth(window: window) > 0
}

@discardableResult
private func withTemporaryWindowMovableEnabled(window: NSWindow?, _ body: () -> Void) -> Bool? {
    guard let window else {
        body()
        return nil
    }

    let previousMovable = window.isMovable
    if !previousMovable {
        window.isMovable = true
    }
    defer {
        window.isMovable = previousMovable
    }

    body()
    return previousMovable
}

private enum StandardTitlebarDoubleClickAction {
    case miniaturize
    case zoom
}

private func resolvedDoubleClickAction() -> StandardTitlebarDoubleClickAction {
    let defaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]

    if let action = (defaults["AppleActionOnDoubleClick"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        if action == "minimize" || action == "miniaturize" {
            return .miniaturize
        }
    }

    if let miniaturizeOnDoubleClick = defaults["AppleMiniaturizeOnDoubleClick"] as? Bool,
       miniaturizeOnDoubleClick
    {
        return .miniaturize
    }

    return .zoom
}

private func performStandardTitlebarDoubleClick(window: NSWindow?) {
    guard let window else { return }
    switch resolvedDoubleClickAction() {
    case .miniaturize:
        window.miniaturize(nil)
    case .zoom:
        window.zoom(nil)
    }
}

/// Dedicated window drag region. Keep background drag disabled globally and
/// route move-window gestures only through this explicit handle.
struct WindowDragHandleView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DraggableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = (nsView, context)
    }

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                performStandardTitlebarDoubleClick(window: window)
                return
            }

            guard !isWindowDragSuppressed(window: window) else {
                return
            }

            if let window {
                _ = withTemporaryWindowMovableEnabled(window: window) {
                    window.performDrag(with: event)
                }
            } else {
                super.mouseDown(with: event)
            }
        }
    }
}

struct WindowDragHandleStrip: View {
    let symbolColor: Color

    init(symbolColor: Color = .secondary) {
        self.symbolColor = symbolColor
    }

    var body: some View {
        ZStack {
            WindowDragHandleView()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(symbolColor)
                .allowsHitTesting(false)
        }
        .frame(width: 32, height: 24)
        .contentShape(Rectangle())
        .accessibilityLabel("Move Window")
    }
}
