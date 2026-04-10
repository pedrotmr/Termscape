import AppKit
import Foundation

/// Owns a `ghostty_surface_t` and the AppKit view hierarchy needed to render it.
/// Adapted from cmux's TerminalSurface — stripped to the essential lifecycle.
@MainActor
final class TerminalSurface: Identifiable {
    let id: UUID
    let workspaceId: UUID

    private(set) var surface: ghostty_surface_t?
    private weak var attachedView: GhosttyNSView?
    private var callbackContext: Unmanaged<GhosttyCallbackContext>?

    private let workingDirectory: String?
    private(set) var currentWorkingDirectory: String?

    /// The AppKit view hierarchy: GhosttySurfaceScrollView > documentView > GhosttyNSView
    let hostedView: GhosttySurfaceScrollView
    private let surfaceView: GhosttyNSView

    var isViewInWindow: Bool { hostedView.window != nil }

    init(workspaceId: UUID, workingDirectory: String? = nil) {
        self.id = UUID()
        self.workspaceId = workspaceId
        let normalizedDirectory = Self.normalizeWorkingDirectoryPath(workingDirectory)
        self.workingDirectory = normalizedDirectory
        self.currentWorkingDirectory = normalizedDirectory

        // Initial non-zero frame so Metal layer initializes correctly
        let view = GhosttyNSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.surfaceView = view
        self.hostedView = GhosttySurfaceScrollView(surfaceView: view)

        view.terminalSurface = self
    }

    // MARK: - Surface lifecycle

    func attachToView(_ view: GhosttyNSView) {
        if attachedView === view && surface != nil { return }
        if let existing = attachedView, existing !== view { return }

        attachedView = view

        guard surface == nil else { return }
        guard view.window != nil else { return }

        createSurface(for: view)
    }

    private func createSurface(for view: GhosttyNSView) {
        guard let app = GhosttyApp.shared.app else {
            print("Ghostty app not initialized")
            return
        }

        let scale = max(1.0,
            view.window?.backingScaleFactor
            ?? view.layer?.contentsScale
            ?? NSScreen.main?.backingScaleFactor
            ?? 1.0
        )

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(view).toOpaque()
        ))
        surfaceConfig.scale_factor = scale
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // Keep this C string alive until ghostty_surface_new consumes it.
        var workingDirectoryCString: UnsafeMutablePointer<CChar>?
        if let wd = currentWorkingDirectory {
            workingDirectoryCString = strdup(wd)
            surfaceConfig.working_directory = UnsafePointer(workingDirectoryCString)
        }
        defer {
            if let ptr = workingDirectoryCString {
                free(ptr)
            }
        }

        // Set up callback context
        let ctx = GhosttyCallbackContext(surfaceId: id, workspaceId: workspaceId)
        let retained = Unmanaged.passRetained(ctx)
        callbackContext?.release()
        callbackContext = retained
        surfaceConfig.userdata = retained.toOpaque()

        // Environment variables
        var envVars: [ghostty_env_var_s] = []
        var envStorage: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
        defer {
            for (k, v) in envStorage { free(k); free(v) }
        }

        func addEnv(_ key: String, _ value: String) {
            let k = strdup(key)!
            let v = strdup(value)!
            envStorage.append((k, v))
            envVars.append(ghostty_env_var_s(key: k, value: v))
        }

        addEnv("TERMSCAPE_SURFACE_ID", id.uuidString)
        addEnv("TERMSCAPE_WORKSPACE_ID", workspaceId.uuidString)

        if !envVars.isEmpty {
            envVars.withUnsafeMutableBufferPointer { buf in
                surfaceConfig.env_vars = buf.baseAddress
                surfaceConfig.env_var_count = buf.count
                self.surface = ghostty_surface_new(app, &surfaceConfig)
            }
        } else {
            self.surface = ghostty_surface_new(app, &surfaceConfig)
        }

        if surface == nil {
            callbackContext?.release()
            callbackContext = nil
            print("Failed to create ghostty surface")
        } else {
            GhosttyApp.shared.registerSurface(self, for: surface!)
            // Give the callback context a direct reference to the surface
            // so clipboard callbacks can use it without going through Swift actors
            ctx.surface = surface
        }
    }

    func teardown() {
        let ctx = callbackContext
        callbackContext = nil

        let s = surface
        surface = nil

        guard let s else {
            ctx?.release()
            return
        }

        GhosttyApp.shared.unregisterSurface(s)

        Task { @MainActor in
            ghostty_surface_free(s)
            ctx?.release()
        }
    }

    func isAttached(to view: GhosttyNSView) -> Bool {
        attachedView === view && surface != nil
    }

    // MARK: - Focus

    func setFocused(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    // MARK: - Text input

    func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    private static let clearScreenAction = "clear_screen"

    /// Clears the screen and scrollback — same as Ghostty’s `clear_screen` binding (default ⌘K).
    func performClearScreen() {
        guard let surface else { return }
        Self.clearScreenAction.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(Self.clearScreenAction.utf8.count))
        }
    }

    var splitWorkingDirectory: String? {
        currentWorkingDirectory ?? workingDirectory
    }

    func updateCurrentWorkingDirectory(_ workingDirectory: String) {
        guard let normalized = Self.normalizeWorkingDirectoryPath(workingDirectory) else { return }
        currentWorkingDirectory = normalized
    }

    static func normalizeWorkingDirectoryPath(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidatePath: String
        if trimmed.lowercased().hasPrefix("file:") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            candidatePath = url.path
        } else {
            candidatePath = (trimmed as NSString).expandingTildeInPath
        }

        guard !candidatePath.isEmpty else { return nil }

        let normalizedPath = URL(fileURLWithPath: candidatePath, isDirectory: true)
            .standardizedFileURL
            .path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        return normalizedPath
    }
}
