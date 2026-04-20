import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    weak static var shared: AppDelegate?
    let appState = AppState()
    private var closeShortcutMonitor: Any?

    override init() {
        super.init()
        AppDelegate.shared = self
        clearSavedWindowStateIfPresent()
    }

    func applicationWillFinishLaunching(_: Notification) {
        // Termscape already persists full workspace/tab layout; AppKit window restoration adds a
        // second state source and can trap users in stale/corrupted restorable state.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func application(_: NSApplication, shouldRestoreApplicationState _: NSCoder) -> Bool {
        false
    }

    func application(_: NSApplication, shouldSaveApplicationState _: NSCoder) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        _ = GhosttyApp.shared // Initialize Ghostty early

        // Load persisted workspaces
        appState.load()

        // Ensure startup has an active workspace when no saved workspaces exist.
        appState.ensureStartupWorkspaceIfNeeded()
        installCloseShortcutMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sender.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quit Termscape?"
        alert.informativeText = "Any running terminals in this app will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_: Notification) {
        if let closeShortcutMonitor {
            NSEvent.removeMonitor(closeShortcutMonitor)
            self.closeShortcutMonitor = nil
        }
        appState.persist()
    }

    private func installCloseShortcutMonitor() {
        closeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chord = flags.intersection([.command, .shift, .option, .control])

            // Route Cmd+W to pane/tab close and prevent the default "Close Window" behavior.
            if chord == .command, event.keyCode == 13 {
                NotificationCenter.default.post(name: .closeTab, object: nil)
                return nil
            }

            return event
        }
    }

    private func clearSavedWindowStateIfPresent() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let savedStatePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Saved Application State")
            .appendingPathComponent("\(bundleIdentifier).savedState")

        guard FileManager.default.fileExists(atPath: savedStatePath.path) else { return }

        do {
            try FileManager.default.removeItem(at: savedStatePath)
        } catch {
            print("Failed to remove saved window state at \(savedStatePath.path): \(error)")
        }
    }
}
