import Observation
import SwiftUI

@Observable
final class ThemeManager {

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.id, forKey: "muxon.selectedThemeId")
            Task { @MainActor in
                GhosttyThemeWriter.apply(current)
            }
        }
    }

    init() {
        let savedId = UserDefaults.standard.string(forKey: "muxon.selectedThemeId")
        self.current = AppTheme.all.first { $0.id == savedId } ?? .tobacco
        // Apply terminal theme on launch
        Task { @MainActor in
            GhosttyThemeWriter.apply(self.current)
        }
    }
}
