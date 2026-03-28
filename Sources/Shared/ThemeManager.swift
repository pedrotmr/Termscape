import Observation
import SwiftUI

@Observable
final class ThemeManager {

    var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.id, forKey: "muxon.selectedThemeId")
        }
    }

    init() {
        let savedId = UserDefaults.standard.string(forKey: "muxon.selectedThemeId")
        self.current = AppTheme.all.first { $0.id == savedId } ?? .tobacco
    }
}
