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

        // Ensure startup has an active workspace when no saved workspaces exist.
        appState.ensureStartupWorkspaceIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.persist()
    }
}
