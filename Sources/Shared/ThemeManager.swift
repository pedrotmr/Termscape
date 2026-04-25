import Observation
import SwiftUI

@Observable
final class ThemeManager {
    /// UserDefaults previously stored these ids before themes were renamed or split.
    private static let legacySelectedThemeIdReplacements: [String: String] = [
        "obsidian": "cursor-dark",
        "cursor": "cursor-dark",
        "vscode-dark-plus": "vscode-dark-modern",
        "tomorrow-night-blue": "night-blue",
    ]

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.id, forKey: "termscape.selectedThemeId")
            applyTerminalThemeIfEnabled()
        }
    }

    var overridesTerminalColors: Bool {
        didSet {
            UserDefaults.standard.set(overridesTerminalColors, forKey: "termscape.overridesTerminalColors")
            if overridesTerminalColors {
                applyTerminalThemeIfEnabled()
            } else {
                Task { @MainActor in GhosttyThemeWriter.removeOverride() }
            }
        }
    }

    init() {
        let rawId = UserDefaults.standard.string(forKey: "termscape.selectedThemeId")
        let savedId = rawId.flatMap { Self.legacySelectedThemeIdReplacements[$0] } ?? rawId
        if let savedId, savedId != rawId {
            UserDefaults.standard.set(savedId, forKey: "termscape.selectedThemeId")
        }
        let overrides = UserDefaults.standard.object(forKey: "termscape.overridesTerminalColors") as? Bool ?? true
        current = AppTheme.all.first { $0.id == savedId } ?? .tobacco
        overridesTerminalColors = overrides
        applyTerminalThemeIfEnabled()
    }

    private func applyTerminalThemeIfEnabled() {
        guard overridesTerminalColors else { return }
        let theme = current
        Task { @MainActor in GhosttyThemeWriter.apply(theme) }
    }
}
