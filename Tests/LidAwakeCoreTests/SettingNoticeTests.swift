import LidAwakeShared
import XCTest
@testable import LidAwakeCore

@MainActor
final class SettingNoticeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingNoticeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.set(true, forKey: SafetyPreferences.Key.watchedAppsTimerMigrated)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: Watched apps

    func testWatchedAppsApplyOnlyWithSleepWhenIdleOutsideKeepScreenOn() {
        XCTAssertTrue(SettingNotice.watchedAppsApply(mode: .off, idleSleepEnabled: true))
        XCTAssertTrue(SettingNotice.watchedAppsApply(mode: .lidClosed, idleSleepEnabled: true))
        XCTAssertFalse(SettingNotice.watchedAppsApply(mode: .keepScreenOn, idleSleepEnabled: true))
        for mode in Mode.allCases {
            XCTAssertFalse(SettingNotice.watchedAppsApply(mode: mode, idleSleepEnabled: false), "\(mode)")
        }
    }

    // MARK: Wake at

    func testWakeOnBatteryOnlyWhenWakeIsOnAndTheMacRunsOnBattery() {
        XCTAssertTrue(SettingNotice.showsWakeOnBattery(wakeEnabled: true, power: .battery))
        XCTAssertFalse(SettingNotice.showsWakeOnBattery(wakeEnabled: true, power: .ac))
        XCTAssertFalse(SettingNotice.showsWakeOnBattery(wakeEnabled: true, power: .unknown))
        XCTAssertFalse(SettingNotice.showsWakeOnBattery(wakeEnabled: false, power: .battery))
    }

    func testPowerStatusFollowsTheSwitchToPower() async {
        let source = SwitchingPowerSource()
        source.reading = PowerReading(battery: .percent(60), source: .battery)
        let monitor = ManualPowerSourceMonitor()
        let status = PowerStatus(source: source, monitor: monitor)
        XCTAssertTrue(SettingNotice.showsWakeOnBattery(wakeEnabled: true, power: status.reading.source))

        source.reading = PowerReading(battery: .percent(60), source: .ac)
        monitor.change()
        for _ in 0..<100 where status.reading.source != .ac {
            await Task.yield()
        }
        XCTAssertFalse(SettingNotice.showsWakeOnBattery(wakeEnabled: true, power: status.reading.source))
    }

    func testPowerStatusRefreshReadsAgain() {
        let source = SwitchingPowerSource()
        let status = PowerStatus(source: source, monitor: ManualPowerSourceMonitor())
        source.reading = PowerReading(battery: .none, source: .ac)
        status.refresh()
        XCTAssertEqual(status.reading, PowerReading(battery: .none, source: .ac))
    }

    // MARK: Sleep when idle

    func testSleepWhenIdleByWakeOnlyForTheSession() {
        let preferences = SafetyPreferences(defaults: defaults)
        XCTAssertFalse(shows(preferences))

        preferences.beginIdleSleepSession()
        XCTAssertTrue(preferences.idleSleepForSessionOnly)
        XCTAssertTrue(shows(preferences))

        preferences.endIdleSleepSession()
        XCTAssertFalse(preferences.idleSleepForSessionOnly)
        XCTAssertFalse(shows(preferences))
    }

    func testSleepWhenIdleTurnedOnByTheUserHasNoSessionLine() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.idleSleepEnabled = true
        preferences.beginIdleSleepSession()
        XCTAssertFalse(shows(preferences), "Already on, so Wake at did not turn it on")
    }

    func testTurningSleepWhenIdleOffAndOnDuringTheSessionMakesItTheUsers() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.beginIdleSleepSession()
        preferences.idleSleepEnabled = false
        XCTAssertFalse(shows(preferences))
        preferences.idleSleepEnabled = true
        XCTAssertFalse(shows(preferences))
    }

    private func shows(_ preferences: SafetyPreferences) -> Bool {
        SettingNotice.showsIdleSleepByWake(
            idleSleepEnabled: preferences.idleSleepEnabled,
            forSessionOnly: preferences.idleSleepForSessionOnly
        )
    }

    // MARK: Turn off after

    func testTimerLineChoice() {
        XCTAssertEqual(
            SettingNotice.timer(setForWatchedApps: true, pendingForWatchedApps: false),
            "Set to 4 hours for watched apps."
        )
        XCTAssertEqual(
            SettingNotice.timer(setForWatchedApps: false, pendingForWatchedApps: true),
            "Will be set to 4 hours for watched apps when the mode ends."
        )
        XCTAssertNil(SettingNotice.timer(setForWatchedApps: false, pendingForWatchedApps: false))
    }

    func testTimerLineFollowsTheWatchedAppsTimer() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.idleSleepEnabled = true
        preferences.modeIsOn = true
        preferences.watchedAppPaths = ["/Applications/Editor.app"]
        XCTAssertEqual(timerLine(preferences), "Will be set to 4 hours for watched apps when the mode ends.")

        preferences.modeIsOn = false
        XCTAssertEqual(timerLine(preferences), "Set to 4 hours for watched apps.")

        preferences.timerSeconds = 7200
        XCTAssertEqual(timerLine(preferences), "Set to 4 hours for watched apps.", "Only turning it off clears it")

        preferences.timerEnabled = false
        XCTAssertNil(timerLine(preferences))
        preferences.timerEnabled = true
        XCTAssertNil(timerLine(preferences), "Turned on by the user")
    }

    func testTimerLineGoesWithAnEmptiedList() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.idleSleepEnabled = true
        preferences.watchedAppPaths = ["/Applications/Editor.app"]
        XCTAssertNotNil(timerLine(preferences))
        preferences.watchedAppPaths = []
        XCTAssertNil(timerLine(preferences))
    }

    func testNoTimerLineWhenTheUserTimerWasAlreadyOn() {
        let preferences = SafetyPreferences(defaults: defaults)
        preferences.timerEnabled = true
        preferences.idleSleepEnabled = true
        preferences.watchedAppPaths = ["/Applications/Editor.app"]
        XCTAssertNil(timerLine(preferences))
    }

    private func timerLine(_ preferences: SafetyPreferences) -> String? {
        SettingNotice.timer(
            setForWatchedApps: preferences.showsWatchedAppsTimerNote,
            pendingForWatchedApps: preferences.showsWatchedAppsTimerPendingNote
        )
    }

    // MARK: No battery

    func testNoBatteryOnlyWithoutAnInternalBattery() {
        XCTAssertTrue(SettingNotice.hasNoBattery(.none))
        XCTAssertFalse(SettingNotice.hasNoBattery(.percent(0)))
        XCTAssertFalse(SettingNotice.hasNoBattery(.percent(80)))
        XCTAssertFalse(SettingNotice.hasNoBattery(.unknown))
    }

    // MARK: Pause banner

    func testPauseBannerSaysTheTimerKeepsCountingOnlyWithTheTimerOn() {
        let base = "Only while charging is on, so Run with Lid Closed waits until power is connected."
        let withTimer = WindowMessage.list(helper: nil, mode: nil, isPausedOnBattery: true, timerIsOn: true)
        XCTAssertEqual(withTimer.first?.text, base + " The timer keeps counting.")
        let withoutTimer = WindowMessage.list(helper: nil, mode: nil, isPausedOnBattery: true, timerIsOn: false)
        XCTAssertEqual(withoutTimer.first?.text, base)
        XCTAssertEqual(WindowMessage.list(helper: nil, mode: nil, isPausedOnBattery: false, timerIsOn: true), [])
    }

    func testTexts() {
        XCTAssertEqual(SettingNotice.watchedAppsUnused, "Works only with Sleep when idle in Run with Lid Closed.")
        XCTAssertEqual(SettingNotice.wakeOnBattery, "The Mac is on battery, so the wake will not turn the mode on.")
        XCTAssertEqual(SettingNotice.idleSleepByWake, "On for this session, turned on by Wake at.")
        XCTAssertEqual(SettingNotice.noBattery, "This Mac has no battery.")
    }
}

private final class SwitchingPowerSource: PowerSourceReading {
    var reading = PowerReading(battery: .percent(80), source: .ac)

    func read() -> PowerReading { reading }
}

private final class ManualPowerSourceMonitor: PowerSourceMonitoring {
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func change() {
        handler?()
    }
}
