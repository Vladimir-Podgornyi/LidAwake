import LidAwakeShared
import XCTest
@testable import LidAwakeCore

@MainActor
final class SafetyPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SafetyPreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testValuesBelowRangeReadAsLowest() {
        defaults.set(0, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(-5, forKey: SafetyPreferences.Key.batteryLimitPercent)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 60)
        XCTAssertEqual(preferences.batteryLimitPercent, 1)
    }

    func testValuesAboveRangeReadAsHighest() {
        defaults.set(100_000, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(150, forKey: SafetyPreferences.Key.batteryLimitPercent)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 86_400)
        XCTAssertEqual(preferences.batteryLimitPercent, 100)
    }

    func testValuesInRangeAreKept() {
        defaults.set(5400, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(35, forKey: SafetyPreferences.Key.batteryLimitPercent)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 5400)
        XCTAssertEqual(preferences.batteryLimitPercent, 35)
    }

    func testClampedValuesAreAcceptedByTheHelper() {
        defaults.set(0, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(true, forKey: SafetyPreferences.Key.timerEnabled)
        defaults.set(0, forKey: SafetyPreferences.Key.batteryLimitPercent)
        defaults.set(true, forKey: SafetyPreferences.Key.batteryLimitEnabled)
        XCTAssertTrue(SafetyPreferences(defaults: defaults).helperSettings.isValid)
    }

    func testDefaults() {
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 7200)
        XCTAssertEqual(preferences.batteryLimitPercent, 20)
    }
}
