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
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let alert = NSAlert()
    alert.messageText = "Quit Termscape?"
    alert.informativeText = "Any running terminals in this app will be closed."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.persist()
  }
}
