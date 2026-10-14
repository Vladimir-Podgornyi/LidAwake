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

    func testSystemWithoutStoredValue() {
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .system)
    }

    func testStoredBlueIsKept() {
        defaults.set("blue", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "blue")
    }

    func testStoredAmberIsKept() {
        defaults.set("amber", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .amber)
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "amber")
    }

    func testStoredSystemIsRead() {
        defaults.set("system", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .system)
    }

    func testUnknownValueReadsAsSystem() {
        defaults.set("green", forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .system)
        defaults.set(1, forKey: "accentTheme")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .system)
    }

    func testChoicesInSwitchOrder() {
        XCTAssertEqual(AccentTheme.allCases, [.blue, .system, .amber])
        XCTAssertEqual(AccentTheme.allCases.map(\.rawValue), ["blue", "system", "amber"])
    }

    func testChoiceIsStored() {
        let preference = AccentPreference(defaults: defaults)
        preference.theme = .amber
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "amber")
        preference.theme = .blue
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "blue")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .blue)
        preference.theme = .system
        XCTAssertEqual(defaults.string(forKey: "accentTheme"), "system")
        XCTAssertEqual(AccentPreference(defaults: defaults).theme, .system)
    }

    func testSystemColorChangeRedrawsOnlySystemAccent() {
        let center = NotificationCenter()
        let name = Notification.Name("AccentTests.systemColorsChanged")
        let preference = AccentPreference(defaults: defaults, systemColorsChanged: name, center: center)
        var changes = 0
        let subscription = preference.objectWillChange.sink { changes += 1 }

        center.post(name: name, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(changes, 1)

        preference.theme = .amber
        changes = 0
        center.post(name: name, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(changes, 0)
        subscription.cancel()
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
        XCTAssertEqual(AccentTheme.blue.color?.value(isDark: false), 0x0B63E5)
        XCTAssertEqual(AccentTheme.blue.color?.value(isDark: true), 0x5B9DFF)
    }

    func testAmberColors() {
        XCTAssertEqual(AccentTheme.amber.color?.value(isDark: false), 0xD98200)
        XCTAssertEqual(AccentTheme.amber.color?.value(isDark: true), 0xF5A623)
    }

    func testSystemHasNoFixedColor() {
        XCTAssertNil(AccentTheme.system.color)
    }

    func testOnAccentColors() {
        XCTAssertEqual(AccentTheme.onAccent.value(isDark: false), 0xFFFFFF)
        XCTAssertEqual(AccentTheme.onAccent.value(isDark: true), 0x17181B)
    }
}
