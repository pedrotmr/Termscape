import SwiftUI
import Bonsplit

struct WorkspaceContainerView: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            if let tab = workspace.selectedTab {
                TabBarView(workspace: workspace)

                CanvasHostingView(tab: tab)
                    .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                        _ = workspace.addTab()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                        // If this tab has multiple panes, Cmd+W closes the focused pane.
                        // Only close the whole tab when it's down to a single pane.
                        if tab.bonsplitController.allPaneIds.count > 1,
                           let focusedPaneId = tab.bonsplitController.focusedPaneId {
                            tab.bonsplitController.closePane(focusedPaneId)
                        } else if let tabId = workspace.selectedTabId {
                            workspace.closeTab(tabId)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitRight)) { _ in
                        splitPane(tab: tab, orientation: .horizontal)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .splitDown)) { _ in
                        splitPane(tab: tab, orientation: .vertical)
                    }
            } else {
                Color.clear
                    .onAppear { workspace.ensureHasTab() }
            }
        }
        .onAppear {
            workspace.ensureHasTab()
        }
    }

    /// Split the current pane and immediately create a terminal tab in the new empty pane.
    /// Bonsplit creates new panes with no tabs — we must add one so the canvas can
    /// attach a TerminalSurface to it.
    private func splitPane(tab: WorkspaceTab, orientation: SplitOrientation) {
        guard let newPaneId = tab.bonsplitController.splitPane(nil, orientation: orientation) else { return }
        // Create a Bonsplit tab in the new pane. This fires didCreateTab → notifyLayoutChanged
        // → CanvasDocumentView creates a TerminalSurface for the new pane.
        tab.bonsplitController.createTab(
            title: "Terminal",
            icon: "terminal",
            kind: "terminal",
            inPane: newPaneId
        )
    }
}
