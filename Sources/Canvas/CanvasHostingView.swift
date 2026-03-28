import SwiftUI
import AppKit

/// NSViewRepresentable bridge that embeds the CanvasScrollView into SwiftUI.
struct CanvasHostingView: NSViewRepresentable {
    @ObservedObject var tab: WorkspaceTab

    func makeNSView(context: Context) -> CanvasScrollView {
        let canvas = CanvasScrollView(frame: .zero)

        // Listen for bonsplit changes to relayout
        context.coordinator.canvas = canvas
        context.coordinator.setupObserver(for: tab)

        return canvas
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        nsView.updateLayout(for: tab)
        context.coordinator.setupObserver(for: tab)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var canvas: CanvasScrollView?
        private var observerToken: NSObjectProtocol?

        func setupObserver(for tab: WorkspaceTab) {
            // Remove previous observer before registering a new one to avoid duplicates.
            if let old = observerToken {
                NotificationCenter.default.removeObserver(old)
            }
            observerToken = NotificationCenter.default.addObserver(
                forName: .bonsplitLayoutDidChange,
                object: tab.bonsplitController,
                queue: .main
            ) { [weak self] _ in
                guard let self, let canvas = self.canvas else { return }
                canvas.updateLayout(for: tab)
            }
        }

        deinit {
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}

extension Notification.Name {
    static let bonsplitLayoutDidChange = Notification.Name("muxon.bonsplitLayoutDidChange")
}
