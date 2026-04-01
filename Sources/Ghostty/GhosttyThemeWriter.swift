import Foundation

/// Writes a Ghostty color config fragment and reloads the running Ghostty app.
///
/// Strategy: on theme change, Termscape writes terminal colors to
/// ~/.config/ghostty/termscape-theme, then creates a fresh config that layers:
///   1. Default files (user's ~/.config/ghostty/config) — preserves font, keybinds, etc.
///   2. Our theme fragment — overrides only colors
///
/// No user setup required. Ghostty is reloaded via ghostty_app_update_config.
@MainActor
enum GhosttyThemeWriter {

    private static let themeFileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ghostty/termscape-theme")

    // MARK: - Public API

    static func apply(_ theme: AppTheme) {
        write(theme.terminalTheme)
        reloadConfig()
    }

    static func removeOverride() {
        try? FileManager.default.removeItem(at: themeFileURL)
        reloadDefaultConfig()
    }

    // MARK: - File writing

    private static func write(_ t: TerminalTheme) {
        // Ensure ~/.config/ghostty/ exists
        let dir = themeFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let content = buildConfig(t)
        try? content.write(to: themeFileURL, atomically: true, encoding: .utf8)
    }

    private static func buildConfig(_ t: TerminalTheme) -> String {
        var lines: [String] = [
            "# Termscape managed — do not edit manually",
            "",
            "background = \(t.background)",
            "foreground = \(t.foreground)",
            "cursor-color = \(t.cursor)",
            "selection-background = \(t.selectionBackground)",
            "selection-foreground = \(t.selectionForeground)",
            "",
        ]
        for (i, hex) in t.palette.enumerated() {
            lines.append("palette = \(i)=\(hex)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Config reload

    private static func reloadConfig() {
        guard let app = GhosttyApp.shared.app,
              let newConfig = ghostty_config_new() else { return }

        ghostty_config_load_default_files(newConfig)
        ghostty_config_load_recursive_files(newConfig)
        ghostty_config_load_file(newConfig, themeFileURL.path(percentEncoded: false))
        ghostty_config_finalize(newConfig)
        ghostty_app_update_config(app, newConfig)
        ghostty_config_free(newConfig)
    }

    private static func reloadDefaultConfig() {
        guard let app = GhosttyApp.shared.app,
              let newConfig = ghostty_config_new() else { return }

        ghostty_config_load_default_files(newConfig)
        ghostty_config_load_recursive_files(newConfig)
        ghostty_config_finalize(newConfig)
        ghostty_app_update_config(app, newConfig)
        ghostty_config_free(newConfig)
    }
}
