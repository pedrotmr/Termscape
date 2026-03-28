import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    let appState = AppState()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = GhosttyApp.shared  // Initialize Ghostty early

        // Load persisted workspaces
        appState.load()

        // Create a default workspace if none exist
        if appState.groups.isEmpty {
            let group = WorkspaceGroup(name: "Workspaces")
            appState.groups.append(group)
            let workspace = appState.addWorkspace(in: group, url: nil)
            appState.selectedWorkspaceId = workspace.id
            workspace.ensureHasTab()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.persist()
    }
}
