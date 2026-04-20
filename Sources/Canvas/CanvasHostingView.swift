import AppKit
import Bonsplit
import SwiftUI

/// NSViewRepresentable bridge that embeds the CanvasScrollView into SwiftUI.
struct CanvasHostingView: NSViewRepresentable {
    @ObservedObject var tab: WorkspaceTab
    @Environment(ThemeManager.self) var theme

    func makeNSView(context: Context) -> CanvasScrollView {
        let canvas = CanvasScrollView(frame: .zero)
        context.coordinator.canvas = canvas
        context.coordinator.setupObserver(for: tab)
        return canvas
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        let t = theme.current
        let tabChanged = nsView.hostedTab !== tab
        nsView.hostedTab = tab
        nsView.applyTheme(
            canvasMatte: t.canvasMatte, paneBackground: t.canvasBackground, accentColor: t.accentNSColor
        )
        if tabChanged {
            nsView.updateLayout(for: tab, options: [])
        }
        context.coordinator.setupObserver(for: tab)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var canvas: CanvasScrollView?
        private var observerToken: NSObjectProtocol?
        private weak var observedController: BonsplitController?
        private weak var observedTab: WorkspaceTab?

        func setupObserver(for tab: WorkspaceTab) {
            if observedController === tab.bonsplitController, observedTab === tab {
                return
            }
            if let old = observerToken {
                NotificationCenter.default.removeObserver(old)
            }
            observedController = tab.bonsplitController
            observedTab = tab
            observerToken = NotificationCenter.default.addObserver(
                forName: .bonsplitLayoutDidChange,
                object: tab.bonsplitController,
                queue: .main
            ) { [weak self] _ in
                guard let self, let canvas, let observedTab else { return }
                canvas.updateLayout(for: observedTab, options: .scrollFocusedPaneIntoView)
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
    static let bonsplitLayoutDidChange = Notification.Name("termscape.bonsplitLayoutDidChange")
}
