import Combine
import XCTest
@testable import LidAwakeCore

@MainActor
final class AccentTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AccentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testBlueWithoutStoredValue() {
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
    }

    func testStoredAmberIsRead() {
        defaults.set("amber", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .amber)
    }

    func testUnknownValueReadsAsBlue() {
        defaults.set("green", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
        defaults.set(1, forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
    }

    func testChoiceIsStored() {
        let preference = AccentPreference(defaults: defaults)
        preference.theme = .amber
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "amber")
        preference.theme = .blue
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "blue")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
    }

    func testChoiceDoesNotTouchSafetySettings() {
        let safety = SafetyPreferences(defaults: defaults)
        var fired = false
        let subscription = safety.changes.sink { fired = true }
        AccentPreference(defaults: defaults).theme = .amber
        XCTAssertFalse(fired)
        subscription.cancel()
    }

    func testBlueColors() {
        XCTAssertEqual(AccentTheme.blue.color.value(isDark: false), 0x0B63E5)
        XCTAssertEqual(AccentTheme.blue.color.value(isDark: true), 0x5B9DFF)
    }

    func testAmberColors() {
        XCTAssertEqual(AccentTheme.amber.color.value(isDark: false), 0xD98200)
        XCTAssertEqual(AccentTheme.amber.color.value(isDark: true), 0xF5A623)
    }

    func testOnAccentColors() {
        XCTAssertEqual(AccentTheme.onAccent.value(isDark: false), 0xFFFFFF)
        XCTAssertEqual(AccentTheme.onAccent.value(isDark: true), 0x17181B)
    }
}
