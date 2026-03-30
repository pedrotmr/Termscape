import Foundation
import SwiftUI
import Bonsplit

@MainActor
final class WorkspaceTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var isPinned: Bool = false
    let workspaceId: UUID

    /// BonsplitController manages the split tree for this tab.
    /// Each tab has an independent layout.
    let bonsplitController: BonsplitController

    /// Terminal surfaces keyed by Bonsplit TabID's UUID.
    var surfaces: [UUID: TerminalSurface] = [:]

    private let workspaceURL: URL?

    init(title: String = "Terminal", workspaceURL: URL?, workspaceId: UUID) {
        self.id = UUID()
        self.title = title
        self.workspaceURL = workspaceURL
        self.workspaceId = workspaceId

        var config = BonsplitConfiguration()
        config.allowSplits = true
        config.autoCloseEmptyPanes = true
        config.appearance.minimumPaneWidth = 600
        config.appearance.minimumPaneHeight = 200
        self.bonsplitController = BonsplitController(configuration: config)

        // Wire delegate so canvas redraws on every layout change (splits, resizes, closes)
        // The delegate is held weakly by BonsplitController, so no retain cycle.
        self.bonsplitController.delegate = self
    }

    /// Create the initial terminal surface for this tab.
    /// Must be called once after init, from the UI layer.
    func createInitialSurface() -> TerminalSurface {
        let surface = TerminalSurface(
            workspaceId: workspaceId,
            workingDirectory: workspaceURL?.path
        )

        // Create the first pane in Bonsplit
        let tabId = bonsplitController.createTab(
            title: title,
            icon: "terminal",
            kind: "terminal"
        )
        if let tabId {
            surfaces[tabId.uuid] = surface
        }

        return surface
    }

    func createSurface(for tabId: TabID) -> TerminalSurface {
        let surface = TerminalSurface(
            workspaceId: workspaceId,
            workingDirectory: workspaceURL?.path
        )
        surfaces[tabId.uuid] = surface
        return surface
    }

    func removeSurface(for tabId: TabID) {
        surfaces[tabId.uuid]?.teardown()
        surfaces.removeValue(forKey: tabId.uuid)
    }

    func teardown() {
        for surface in surfaces.values {
            surface.teardown()
        }
        surfaces.removeAll()
    }
}

// MARK: - BonsplitDelegate

extension WorkspaceTab: BonsplitDelegate {
    /// Post the notification that CanvasHostingView listens for, triggering a canvas relayout.
    func notifyLayoutChanged() {
        NotificationCenter.default.post(name: .bonsplitLayoutDidChange, object: bonsplitController)
    }

    // Canvas needs to redraw whenever a tab is created (new pane tab → needs a surface)
    func splitTabBar(_ controller: BonsplitController, didCreateTab tab: Bonsplit.Tab, inPane pane: PaneID) {
        notifyLayoutChanged()
    }

    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {
        // Note: new pane is empty (no tabs yet). WorkspaceContainerView calls createTab
        // immediately after, which fires didCreateTab → notifyLayoutChanged.
        // We don't notify here to avoid a redundant update with an empty pane.
    }

    /// Teardown the TerminalSurface for the closed tab so Ghostty frees its resources.
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {
        removeSurface(for: tabId)
    }

    func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID) {
        notifyLayoutChanged()
    }

    func splitTabBar(_ controller: BonsplitController, didChangeGeometry snapshot: LayoutSnapshot) {
        notifyLayoutChanged()
    }
}
