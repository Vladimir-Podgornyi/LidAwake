import Combine
import XCTest
@testable import LidAwakeCore

@MainActor
final class WindowAppearanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WindowAppearanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testGlassWithoutStoredValue() {
        XCTAssertEqual(WindowAppearancePreference(defaults: defaults).style, .glass)
    }

    func testStoredSolidIsRead() {
        defaults.set("solid", forKey: "windowStyle")
        XCTAssertEqual(WindowAppearancePreference(defaults: defaults).style, .solid)
    }

    func testUnknownValueReadsAsGlass() {
        defaults.set("frosted", forKey: "windowStyle")
        XCTAssertEqual(WindowAppearancePreference(defaults: defaults).style, .glass)
        defaults.set(1, forKey: "windowStyle")
        XCTAssertEqual(WindowAppearancePreference(defaults: defaults).style, .glass)
    }

    func testChoiceIsStored() {
        let preference = WindowAppearancePreference(defaults: defaults)
        preference.style = .solid
        XCTAssertEqual(defaults.string(forKey: "windowStyle"), "solid")
        preference.style = .glass
        XCTAssertEqual(defaults.string(forKey: "windowStyle"), "glass")
        XCTAssertEqual(WindowAppearancePreference(defaults: defaults).style, .glass)
    }

    func testChoiceDoesNotTouchSafetySettings() {
        let safety = SafetyPreferences(defaults: defaults)
        var fired = false
        let subscription = safety.changes.sink { fired = true }
        WindowAppearancePreference(defaults: defaults).style = .solid
        XCTAssertFalse(fired)
        subscription.cancel()
    }

    func testSystem26UsesTheChoice() {
        XCTAssertEqual(WindowLook(style: .glass, isSystem26OrLater: true, reduceTransparency: false), .glass)
        XCTAssertEqual(WindowLook(style: .solid, isSystem26OrLater: true, reduceTransparency: false), .solid)
    }

    func testOlderSystemKeepsStandardLookForAnyChoice() {
        for style in WindowAppearance.allCases {
            for reduce in [false, true] {
                let look = WindowLook(style: style, isSystem26OrLater: false, reduceTransparency: reduce)
                XCTAssertEqual(look, .standard)
                XCTAssertFalse(look.drawsOwnBackground)
                XCTAssertFalse(look.hasTranslucentCards)
            }
        }
    }

    func testStyleRowOnlyOnSystem26() {
        XCTAssertTrue(WindowLook.showsStyleSetting(isSystem26OrLater: true))
        XCTAssertFalse(WindowLook.showsStyleSetting(isSystem26OrLater: false))
    }

    func testGlassWithReduceTransparencyHasOpaqueCardsAndSystemBackground() {
        let look = WindowLook(style: .glass, isSystem26OrLater: true, reduceTransparency: true)
        XCTAssertEqual(look, .glassOpaqueCards)
        XCTAssertFalse(look.hasTranslucentCards)
        XCTAssertFalse(look.drawsOwnBackground)
    }

    func testSolidIgnoresReduceTransparency() {
        XCTAssertEqual(WindowLook(style: .solid, isSystem26OrLater: true, reduceTransparency: true), .solid)
    }

    func testBackgroundAndCardsPerLook() {
        XCTAssertTrue(WindowLook.glass.hasTranslucentCards)
        XCTAssertFalse(WindowLook.glass.drawsOwnBackground)
        XCTAssertTrue(WindowLook.solid.drawsOwnBackground)
        XCTAssertFalse(WindowLook.solid.hasTranslucentCards)
    }

    func testGlassCardFill() {
        XCTAssertEqual(GlassCard.fill.value(isDark: false), .init(rgb: 0xFFFFFF, opacity: 0.50))
        XCTAssertEqual(GlassCard.fill.value(isDark: true), .init(rgb: 0xFFFFFF, opacity: 0.07))
    }

    func testGlassCardBorder() {
        XCTAssertEqual(GlassCard.border.value(isDark: false), .init(rgb: 0x000000, opacity: 0.10))
        XCTAssertEqual(GlassCard.border.value(isDark: true), .init(rgb: 0xFFFFFF, opacity: 0.14))
    }
}
