import Observation
import SwiftUI

@Observable
final class ThemeManager {
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
        let savedId = UserDefaults.standard.string(forKey: "termscape.selectedThemeId")
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
