@testable import Termscape
import XCTest

@MainActor
final class ThemeManagerTests: XCTestCase {
    private let selectedThemeKey = "termscape.selectedThemeId"
    private let overridesKey = "termscape.overridesTerminalColors"
    private var previousSelectedTheme: String?
    private var hadPreviousSelectedTheme = false
    private var previousOverrides: Bool?
    private var hadPreviousOverrides = false

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard

        hadPreviousSelectedTheme = defaults.object(forKey: selectedThemeKey) != nil
        previousSelectedTheme = defaults.string(forKey: selectedThemeKey)
        hadPreviousOverrides = defaults.object(forKey: overridesKey) != nil
        previousOverrides = defaults.object(forKey: overridesKey) as? Bool

        // Keep tests deterministic and avoid async Ghostty writes in init.
        defaults.set(false, forKey: overridesKey)
        defaults.removeObject(forKey: selectedThemeKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard

        if hadPreviousSelectedTheme {
            defaults.set(previousSelectedTheme, forKey: selectedThemeKey)
        } else {
            defaults.removeObject(forKey: selectedThemeKey)
        }

        if hadPreviousOverrides {
            defaults.set(previousOverrides, forKey: overridesKey)
        } else {
            defaults.removeObject(forKey: overridesKey)
        }

        super.tearDown()
    }

    func testLegacyObsidianThemeIdMapsToCursorDark() {
        let defaults = UserDefaults.standard
        defaults.set("obsidian", forKey: selectedThemeKey)

        let manager = ThemeManager()

        XCTAssertEqual(manager.current.id, "cursor-dark")
        XCTAssertEqual(defaults.string(forKey: selectedThemeKey), "cursor-dark")
    }

    func testLegacyCursorThemeIdMapsToCursorDark() {
        let defaults = UserDefaults.standard
        defaults.set("cursor", forKey: selectedThemeKey)

        let manager = ThemeManager()

        XCTAssertEqual(manager.current.id, "cursor-dark")
        XCTAssertEqual(defaults.string(forKey: selectedThemeKey), "cursor-dark")
    }

    func testLegacyVSCodeThemeIdMapsToDarkModern() {
        let defaults = UserDefaults.standard
        defaults.set("vscode-dark-plus", forKey: selectedThemeKey)

        let manager = ThemeManager()

        XCTAssertEqual(manager.current.id, "vscode-dark-modern")
        XCTAssertEqual(defaults.string(forKey: selectedThemeKey), "vscode-dark-modern")
    }

    func testLegacyTomorrowNightBlueThemeIdMapsToNightBlue() {
        let defaults = UserDefaults.standard
        defaults.set("tomorrow-night-blue", forKey: selectedThemeKey)

        let manager = ThemeManager()

        XCTAssertEqual(manager.current.id, "night-blue")
        XCTAssertEqual(defaults.string(forKey: selectedThemeKey), "night-blue")
    }
}
