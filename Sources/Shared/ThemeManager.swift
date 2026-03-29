import Observation
import SwiftUI

@Observable
final class ThemeManager {

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.id, forKey: "muxon.selectedThemeId")
            applyTerminalThemeIfEnabled()
        }
    }

    var overridesTerminalColors: Bool {
        didSet {
            UserDefaults.standard.set(overridesTerminalColors, forKey: "muxon.overridesTerminalColors")
            if overridesTerminalColors {
                applyTerminalThemeIfEnabled()
            } else {
                Task { @MainActor in GhosttyThemeWriter.removeOverride() }
            }
        }
    }

    init() {
        let savedId = UserDefaults.standard.string(forKey: "muxon.selectedThemeId")
        let overrides = UserDefaults.standard.object(forKey: "muxon.overridesTerminalColors") as? Bool ?? true
        self.current = AppTheme.all.first { $0.id == savedId } ?? .tobacco
        self.overridesTerminalColors = overrides
        applyTerminalThemeIfEnabled()
    }

    private func applyTerminalThemeIfEnabled() {
        guard overridesTerminalColors else { return }
        let theme = current
        Task { @MainActor in GhosttyThemeWriter.apply(theme) }
    }
}
