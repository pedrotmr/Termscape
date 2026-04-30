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
        let rawSavedId = UserDefaults.standard.string(forKey: "termscape.selectedThemeId")
        let savedId = Self.resolveThemeId(rawSavedId)
        let overrides = UserDefaults.standard.object(forKey: "termscape.overridesTerminalColors") as? Bool ?? true
        let resolvedTheme = AppTheme.all.first { $0.id == savedId } ?? .tobacco
        if rawSavedId != nil, resolvedTheme.id != rawSavedId {
            UserDefaults.standard.set(resolvedTheme.id, forKey: "termscape.selectedThemeId")
        }
        current = resolvedTheme
        overridesTerminalColors = overrides
        applyTerminalThemeIfEnabled()
    }

    private static func resolveThemeId(_ persistedThemeId: String?) -> String? {
        guard let persistedThemeId else { return nil }
        if AppTheme.all.contains(where: { $0.id == persistedThemeId }) {
            return persistedThemeId
        }
        guard let replacementId = legacySelectedThemeIdReplacements[persistedThemeId] else {
            return nil
        }
        return AppTheme.all.contains(where: { $0.id == replacementId }) ? replacementId : nil
    }

    private func applyTerminalThemeIfEnabled() {
        guard overridesTerminalColors else { return }
        let theme = current
        Task { @MainActor in GhosttyThemeWriter.apply(theme) }
    }
}
