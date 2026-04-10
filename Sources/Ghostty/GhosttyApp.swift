import AppKit
import Foundation

/// Singleton that owns the `ghostty_app_t` runtime.
/// Adapted from cmux's GhosttyApp — stripped of telemetry, remote daemon, and CJK font fallbacks.
@MainActor
final class GhosttyApp {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    private final class WeakSurfaceRef {
        weak var surface: TerminalSurface?

        init(surface: TerminalSurface) {
            self.surface = surface
        }
    }

    private var surfaceRefsByHandle: [UInt: WeakSurfaceRef] = [:]
    private var appObservers: [NSObjectProtocol] = []

    private init() {
        initializeGhostty()
    }

    private func initializeGhostty() {
        if getenv("NO_COLOR") != nil { unsetenv("NO_COLOR") }

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            print("Failed to initialize ghostty: \(result)")
            return
        }

        guard let primaryConfig = ghostty_config_new() else {
            print("Failed to create ghostty config")
            return
        }

        ghostty_config_load_default_files(primaryConfig)
        ghostty_config_load_recursive_files(primaryConfig)
        ghostty_config_finalize(primaryConfig)

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true

        runtimeConfig.wakeup_cb = { _ in
            DispatchQueue.main.async {
                GhosttyApp.shared.tick()
            }
        }

        runtimeConfig.action_cb = { _, target, action in
            GhosttyApp.handleRuntimeAction(target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let ctx = GhosttyCallbackContext.from(userdata) else { return }
            let surface = ctx.surface
            guard let surface else { return }

            let pasteboard = GhosttyClipboard.pasteboard(for: location)
            let value = pasteboard.flatMap { GhosttyClipboard.stringContents(from: $0) } ?? ""
            value.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
            }
        }

        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, _ in
            guard let content else { return }
            guard let ctx = GhosttyCallbackContext.from(userdata) else { return }
            guard let surface = ctx.surface else { return }
            // Deny by default — programs should not silently read the clipboard (OSC 52).
            ghostty_surface_complete_clipboard_request(surface, content, state, false)
        }

        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            guard let content, len > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: Int(len))
            var fallback: String?
            for item in buffer {
                guard let dataPtr = item.data else { continue }
                let value = String(cString: dataPtr)
                if let mimePtr = item.mime {
                    let mime = String(cString: mimePtr)
                    if mime.hasPrefix("text/plain") {
                        GhosttyClipboard.writeString(value, to: location)
                        return
                    }
                }
                if fallback == nil { fallback = value }
            }
            if let fallback { GhosttyClipboard.writeString(fallback, to: location) }
        }

        runtimeConfig.close_surface_cb = { userdata, needsConfirmClose in
            guard let ctx = GhosttyCallbackContext.from(userdata) else { return }
            let surfaceId = ctx.surfaceId
            let workspaceId = ctx.workspaceId

            guard !needsConfirmClose else { return }

            DispatchQueue.main.async {
                guard let appState = AppDelegate.shared?.appState else { return }
                // Use workspaceId to narrow the search instead of scanning all groups/workspaces.
                guard let workspace = appState.groups.lazy.flatMap(\.workspaces)
                    .first(where: { $0.id == workspaceId }) else { return }
                for tab in workspace.tabs {
                    if tab.surfaces[surfaceId] != nil {
                        tab.surfaces[surfaceId]?.teardown()
                        tab.surfaces.removeValue(forKey: surfaceId)
                        return
                    }
                }
            }
        }

        if let created = ghostty_app_new(&runtimeConfig, primaryConfig) {
            self.app = created
            self.config = primaryConfig
            NotificationCenter.default.post(name: .ghosttyConfigDidReload, object: nil)
        } else {
            ghostty_config_free(primaryConfig)
            guard let fallbackConfig = ghostty_config_new() else { return }
            ghostty_config_finalize(fallbackConfig)
            guard let created = ghostty_app_new(&runtimeConfig, fallbackConfig) else {
                ghostty_config_free(fallbackConfig)
                print("Failed to create ghostty app")
                return
            }
            self.app = created
            self.config = fallbackConfig
            NotificationCenter.default.post(name: .ghosttyConfigDidReload, object: nil)
        }

        ghostty_app_set_focus(app, NSApp.isActive)

        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, true)
        })

        appObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, false)
        })
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// Ghostty invokes `action_cb` from an arbitrary thread; keep this `nonisolated` and hop to the main queue for AppKit and `surfaceRefsByHandle`.
    nonisolated private static func handleRuntimeAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return true
        case GHOSTTY_ACTION_PWD:
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
            let surfaceKey = surfaceHandle(for: target.target.surface)
            guard let pwdCString = action.action.pwd.pwd else { return false }
            let path = String(cString: pwdCString)
            DispatchQueue.main.async {
                GhosttyApp.shared.applyPwdUpdate(surfaceKey: surfaceKey, path: path)
            }
            return true
        default:
            return false
        }
    }

    private func applyPwdUpdate(surfaceKey: UInt, path: String) {
        guard let surface = surface(forSurfaceKey: surfaceKey) else { return }
        surface.updateCurrentWorkingDirectory(path)
    }

    func registerSurface(_ terminalSurface: TerminalSurface, for handle: ghostty_surface_t) {
        surfaceRefsByHandle[Self.surfaceHandle(for: handle)] = WeakSurfaceRef(surface: terminalSurface)
    }

    func unregisterSurface(_ handle: ghostty_surface_t) {
        surfaceRefsByHandle.removeValue(forKey: Self.surfaceHandle(for: handle))
    }

    private func surface(forSurfaceKey key: UInt) -> TerminalSurface? {
        guard let ref = surfaceRefsByHandle[key] else { return nil }
        guard let surface = ref.surface else {
            surfaceRefsByHandle.removeValue(forKey: key)
            return nil
        }
        return surface
    }

    nonisolated private static func surfaceHandle(for surface: ghostty_surface_t) -> UInt {
        UInt(bitPattern: surface)
    }
}

// MARK: - Callback context

/// Holds per-surface state needed by Ghostty C callbacks.
/// Must be safe to retain/release from non-main-actor contexts.
/// `surface` is accessed from both @MainActor code and C callbacks (potentially any thread),
/// so access is synchronized via a lock.
final class GhosttyCallbackContext: @unchecked Sendable {
    let surfaceId: UUID
    let workspaceId: UUID

    private let lock = NSLock()
    private var _surface: ghostty_surface_t?

    /// The C surface pointer — set after surface creation, read by clipboard callbacks.
    var surface: ghostty_surface_t? {
        get { lock.withLock { _surface } }
        set { lock.withLock { _surface = newValue } }
    }

    init(surfaceId: UUID, workspaceId: UUID) {
        self.surfaceId = surfaceId
        self.workspaceId = workspaceId
    }

    static func from(_ ptr: UnsafeMutableRawPointer?) -> GhosttyCallbackContext? {
        guard let ptr else { return nil }
        return Unmanaged<GhosttyCallbackContext>.fromOpaque(ptr).takeUnretainedValue()
    }
}

// MARK: - Clipboard helper

enum GhosttyClipboard {
    static func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD: return .general
        case GHOSTTY_CLIPBOARD_SELECTION: return NSPasteboard(name: .init("Selection"))
        default: return .general
        }
    }

    static func stringContents(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: .string)
    }

    static func writeString(_ string: String, to location: ghostty_clipboard_e) {
        let pb = Self.pasteboard(for: location) ?? .general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
