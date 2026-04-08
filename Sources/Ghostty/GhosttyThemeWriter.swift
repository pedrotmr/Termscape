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
        do {
            try FileManager.default.removeItem(at: themeFileURL)
        } catch {
            // File may not exist — that's fine; log other errors.
            if (error as NSError).code != NSFileNoSuchFileError {
                print("[Termscape] Failed to remove theme override: \(error)")
            }
        }
        reloadDefaultConfig()
    }

    // MARK: - File writing

    private static func write(_ t: TerminalTheme) {
        let dir = themeFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[Termscape] Failed to create ghostty config dir: \(error)")
            return
        }

        let content = buildConfig(t)
        do {
            try content.write(to: themeFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("[Termscape] Failed to write theme file: \(error)")
        }
    }

    private static func buildConfig(_ t: TerminalTheme) -> String {
        let palette = adjustedPaletteForLegibility(t)
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
        for (i, hex) in palette.enumerated() {
            lines.append("palette = \(i)=\(hex)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// zsh/fish autosuggestions often use ANSI bright-black (palette index 8). Some themes
    /// make that slot too close to the background, so we lift only that color when needed.
    private static func adjustedPaletteForLegibility(_ theme: TerminalTheme) -> [String] {
        let suggestionColorIndex = 8
        let minimumContrast: Double = 3.0

        guard theme.palette.indices.contains(suggestionColorIndex),
              let background = RGBColor(hex: theme.background),
              let foreground = RGBColor(hex: theme.foreground),
              let dimSuggestion = RGBColor(hex: theme.palette[suggestionColorIndex]) else {
            return theme.palette
        }

        if contrastRatio(dimSuggestion, background) >= minimumContrast {
            return theme.palette
        }

        var adjusted = theme.palette
        let blendSteps: [Double] = [0.20, 0.35, 0.50, 0.65, 0.80, 1.0]
        var lifted = dimSuggestion

        for step in blendSteps {
            lifted = dimSuggestion.blended(toward: foreground, amount: step)
            if contrastRatio(lifted, background) >= minimumContrast {
                adjusted[suggestionColorIndex] = lifted.hexString
                return adjusted
            }
        }

        adjusted[suggestionColorIndex] = lifted.hexString
        return adjusted
    }

    private static func contrastRatio(_ a: RGBColor, _ b: RGBColor) -> Double {
        let l1 = a.relativeLuminance
        let l2 = b.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private struct RGBColor {
        let red: Double
        let green: Double
        let blue: Double

        init?(hex: String) {
            let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
            guard normalized.count == 6, let int = UInt32(normalized, radix: 16) else { return nil }
            red = Double((int >> 16) & 0xFF) / 255.0
            green = Double((int >> 8) & 0xFF) / 255.0
            blue = Double(int & 0xFF) / 255.0
        }

        var hexString: String {
            let r = Int((red * 255.0).rounded())
            let g = Int((green * 255.0).rounded())
            let b = Int((blue * 255.0).rounded())
            return String(format: "#%02X%02X%02X", r, g, b)
        }

        var relativeLuminance: Double {
            (0.2126 * linearized(red)) + (0.7152 * linearized(green)) + (0.0722 * linearized(blue))
        }

        func blended(toward target: RGBColor, amount: Double) -> RGBColor {
            let clamped = max(0, min(1, amount))
            return RGBColor(
                red: red + ((target.red - red) * clamped),
                green: green + ((target.green - green) * clamped),
                blue: blue + ((target.blue - blue) * clamped)
            )
        }

        private init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        private func linearized(_ value: Double) -> Double {
            value <= 0.03928 ? (value / 12.92) : pow((value + 0.055) / 1.055, 2.4)
        }
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
