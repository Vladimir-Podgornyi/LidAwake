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
        defaults.set(0, forKey: SafetyPreferences.Key.idleSleepMinutes)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 60)
        XCTAssertEqual(preferences.batteryLimitPercent, 1)
        XCTAssertEqual(preferences.idleSleepMinutes, 1)
    }

    func testValuesAboveRangeReadAsHighest() {
        defaults.set(100_000, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(150, forKey: SafetyPreferences.Key.batteryLimitPercent)
        defaults.set(1000, forKey: SafetyPreferences.Key.idleSleepMinutes)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 86_400)
        XCTAssertEqual(preferences.batteryLimitPercent, 100)
        XCTAssertEqual(preferences.idleSleepMinutes, 240)
    }

    func testValuesInRangeAreKept() {
        defaults.set(5400, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(35, forKey: SafetyPreferences.Key.batteryLimitPercent)
        defaults.set(45, forKey: SafetyPreferences.Key.idleSleepMinutes)
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 5400)
        XCTAssertEqual(preferences.batteryLimitPercent, 35)
        XCTAssertEqual(preferences.idleSleepMinutes, 45)
    }

    func testClampedValuesAreAcceptedByTheHelper() {
        defaults.set(0, forKey: SafetyPreferences.Key.timerSeconds)
        defaults.set(true, forKey: SafetyPreferences.Key.timerEnabled)
        defaults.set(0, forKey: SafetyPreferences.Key.batteryLimitPercent)
        defaults.set(true, forKey: SafetyPreferences.Key.batteryLimitEnabled)
        defaults.set(0, forKey: SafetyPreferences.Key.idleSleepMinutes)
        defaults.set(true, forKey: SafetyPreferences.Key.idleSleepEnabled)
        XCTAssertTrue(SafetyPreferences(defaults: defaults).helperSettings.isValid)
    }

    func testIdleSleepIsSentOnlyWhenOn() {
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertFalse(preferences.idleSleepEnabled)
        XCTAssertEqual(preferences.helperSettings.idleSleepMinutes, 0)

        preferences.idleSleepEnabled = true
        preferences.idleSleepMinutes = 30
        XCTAssertEqual(preferences.helperSettings.idleSleepMinutes, 30)

        preferences.idleSleepEnabled = false
        XCTAssertEqual(preferences.helperSettings.idleSleepMinutes, 0)
        XCTAssertEqual(preferences.idleSleepMinutes, 30)
    }

    func testIdleSleepChoicesAreAcceptedByTheHelper() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.idleSleepEnabled = true
        for minutes in SafetyPreferences.idleSleepChoices {
            preferences.idleSleepMinutes = minutes
            XCTAssertTrue(preferences.helperSettings.isValid, "\(minutes)")
        }
    }

    func testOnlyWhileChargingSendsNoBatteryLimit() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.batteryLimitEnabled = true
        preferences.batteryLimitPercent = 30
        preferences.chargingOnlyEnabled = true
        XCTAssertFalse(preferences.batteryLimitApplies)
        XCTAssertEqual(preferences.helperSettings.batteryLimitPercent, 0)
        XCTAssertTrue(preferences.helperSettings.chargingOnly)
    }

    func testBatteryLimitIsSentWithoutOnlyWhileCharging() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.batteryLimitEnabled = true
        preferences.batteryLimitPercent = 30
        preferences.chargingOnlyEnabled = false
        XCTAssertTrue(preferences.batteryLimitApplies)
        XCTAssertEqual(preferences.helperSettings.batteryLimitPercent, 30)

        preferences.batteryLimitEnabled = false
        XCTAssertEqual(preferences.helperSettings.batteryLimitPercent, 0)
    }

    func testOnlyWhileChargingKeepsTheSavedBatteryLimit() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.batteryLimitEnabled = true
        preferences.batteryLimitPercent = 40

        preferences.chargingOnlyEnabled = true
        XCTAssertTrue(preferences.batteryLimitEnabled)
        XCTAssertEqual(preferences.batteryLimitPercent, 40)
        XCTAssertTrue(defaults.bool(forKey: SafetyPreferences.Key.batteryLimitEnabled))
        XCTAssertEqual(defaults.integer(forKey: SafetyPreferences.Key.batteryLimitPercent), 40)

        preferences.chargingOnlyEnabled = false
        XCTAssertTrue(preferences.batteryLimitEnabled)
        XCTAssertEqual(preferences.batteryLimitPercent, 40)
        XCTAssertEqual(preferences.helperSettings.batteryLimitPercent, 40)

        let reloaded = SafetyPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.batteryLimitEnabled)
        XCTAssertEqual(reloaded.batteryLimitPercent, 40)
    }

    func testDefaults() {
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(preferences.timerSeconds, 7200)
        XCTAssertEqual(preferences.batteryLimitPercent, 20)
        XCTAssertFalse(preferences.idleSleepEnabled)
        XCTAssertEqual(preferences.idleSleepMinutes, 20)
    }

    func testEndingIdleSleepSessionKeepsMinutesAndSendsNothing() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.idleSleepEnabled = true
        preferences.idleSleepMinutes = 30
        var fired = 0
        let subscription = preferences.changes.sink { fired += 1 }

        preferences.endIdleSleepSession()
        subscription.cancel()
        XCTAssertFalse(preferences.idleSleepEnabled)
        XCTAssertEqual(preferences.idleSleepMinutes, 30)
        XCTAssertEqual(preferences.helperSettings.idleSleepMinutes, 0)
        XCTAssertEqual(fired, 0)

        let reloaded = SafetyPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.idleSleepEnabled)
        XCTAssertEqual(reloaded.idleSleepMinutes, 30)
    }

    func testChangesFireAgainAfterEndingIdleSleepSession() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.endIdleSleepSession()
        var fired = 0
        let subscription = preferences.changes.sink { fired += 1 }

        preferences.idleSleepEnabled = true
        preferences.endIdleSleepSession()
        preferences.idleSleepEnabled = true
        subscription.cancel()
        XCTAssertEqual(fired, 2)
    }
}
