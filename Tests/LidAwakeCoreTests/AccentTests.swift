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

    func testContrastRatio() {
        XCTAssertEqual(Contrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0x007AFF, 0x007AFF), 1, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio(0xFFFFFF, 0x007AFF), 4.02, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(0x17181B, 0x007AFF), 4.42, accuracy: 0.01)
    }

    /// The accent colors macOS 26.6 gives for each choice, as sRGB in the light and the dark
    /// appearance, and the symbol drawn on them.
    private static let macAccents: [(name: String, light: UInt32, dark: UInt32, onLight: UInt32, onDark: UInt32)] = [
        ("blue", 0x007AFF, 0x007AFF, 0xFFFFFF, 0x17181B),
        ("purple", 0x953D96, 0xA550A7, 0xFFFFFF, 0x17181B),
        ("pink", 0xF74F9E, 0xF74F9E, 0xFFFFFF, 0x17181B),
        ("red", 0xE0383E, 0xFF5257, 0xFFFFFF, 0x17181B),
        ("orange", 0xF7821B, 0xF7821B, 0x17181B, 0x17181B),
        ("yellow", 0xFFC726, 0xFFC600, 0x17181B, 0x17181B),
        ("green", 0x62BA46, 0x62BA46, 0x17181B, 0x17181B),
        ("graphite", 0x989898, 0x8C8C8C, 0x17181B, 0x17181B),
    ]

    func testSymbolOnMacAccents() {
        for accent in Self.macAccents {
            XCTAssertEqual(AccentTheme.onSystemAccent(accent.light, isDark: false), accent.onLight, accent.name)
            XCTAssertEqual(AccentTheme.onSystemAccent(accent.dark, isDark: true), accent.onDark, accent.name)
        }
    }

    func testSymbolOnMacAccentsIsReadable() {
        for accent in Self.macAccents {
            for (color, isDark) in [(accent.light, false), (accent.dark, true)] {
                let symbol = AccentTheme.onSystemAccent(color, isDark: isDark)
                XCTAssertGreaterThanOrEqual(Contrast.ratio(symbol, color), 3, "\(accent.name) dark=\(isDark)")
            }
        }
    }

    func testDarkSymbolOnYellowInLightAppearance() {
        XCTAssertEqual(AccentTheme.onSystemAccent(0xFFC726, isDark: false), 0x17181B)
    }

    func testUsualSymbolKeptFrom3Up() {
        // White 3.45, dark 5.14: white stays in the light appearance though dark has more.
        XCTAssertEqual(AccentTheme.onSystemAccent(0x8A8A8A, isDark: false), 0xFFFFFF)
        // White 5.02, dark 3.53: dark stays in the dark appearance.
        XCTAssertEqual(AccentTheme.onSystemAccent(0x6F6F6F, isDark: true), 0x17181B)
    }
}
