import LidAwakeShared
import XCTest
@testable import LidAwakeCore

/// The calls of all fakes in the order they were made.
@MainActor
private final class Journal {
    var calls: [String] = []
}

@MainActor
private final class FakeHelper: HelperPreparing {
    var ready = true
    private(set) var readyChecks = 0

    func prepareForSession() async throws {}

    func isReady() async -> Bool {
        readyChecks += 1
        return ready
    }
}

@MainActor
private final class FakeWakeService: ScheduledWakeService {
    var wakes: [Date] = []
    var setError: Error?
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
    }

    func setScheduledWake(minuteOfDay: Int) async throws {
        journal.calls.append("set \(minuteOfDay)")
        if let setError { throw setError }
    }

    func scheduledWakes() async throws -> [Date] {
        journal.calls.append("read")
        return wakes
    }
}

@MainActor
private final class FakeModeStarter: ScheduledModeStarting {
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
    }

    func turnOnBySchedule() async {
        journal.calls.append("mode")
    }
}

@MainActor
private final class FakeLog: ActivityLogging {
    private(set) var events: [ActivityEvent] = []

    func record(_ event: ActivityEvent, at time: Date?) {
        events.append(event)
    }
}

private final class FakeClockMonitor: ClockChangeMonitoring {
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func change() {
        handler?()
    }
}

private final class FakeSleepMonitor: SystemSleepMonitoring {
    private var handler: ((Bool) -> Void)?

    func start(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func change(asleep: Bool) {
        handler?(asleep)
    }
}

@MainActor
final class WakeSchedulerTests: XCTestCase {
    private let journal = Journal()
    private let helper = FakeHelper()
    private lazy var service = FakeWakeService(journal: journal)
    private lazy var mode = FakeModeStarter(journal: journal)
    private let log = FakeLog()
    private let clock = FakeClockMonitor()
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let suiteName = "WakeSchedulerTests-\(UUID().uuidString)"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!
    private lazy var preferences = WakePreferences(defaults: defaults)
    /// Kept so the scheduler outlives the calls it starts on its own.
    private var scheduler: WakeScheduler?

    /// The scheduled time the tests wake around.
    private let wakeTime = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeScheduler() -> WakeScheduler {
        let scheduler = WakeScheduler(
            preferences: preferences,
            helper: helper,
            service: service,
            mode: mode,
            log: log,
            clockMonitor: clock,
            now: { [unowned self] in now }
        )
        scheduler.start()
        self.scheduler = scheduler
        return scheduler
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() {
            await Task.yield()
        }
    }

    /// A scheduler that remembers `wakeTime` with the setting on; the journal starts empty.
    private func scheduledAtWakeTime() async -> WakeScheduler {
        preferences.wakeEnabled = true
        service.wakes = [wakeTime, wakeTime.addingTimeInterval(86_400)]
        let scheduler = makeScheduler()
        await scheduler.sync()
        XCTAssertEqual(scheduler.scheduledWakes, service.wakes)
        journal.calls = []
        return scheduler
    }

    private func wake(_ scheduler: WakeScheduler, after seconds: TimeInterval) async {
        now = wakeTime.addingTimeInterval(seconds)
        scheduler.macDidWake()
        await settle { journal.calls.contains("read") }
    }

    // MARK: Setting

    func testSettingDefaults() {
        XCTAssertFalse(preferences.wakeEnabled)
        XCTAssertEqual(preferences.wakeMinuteOfDay, 480)
        XCTAssertEqual(preferences.helperMinuteOfDay, -1)
    }

    func testSettingIsReadFromTheKeys() {
        defaults.set(true, forKey: "wakeEnabled")
        defaults.set(390, forKey: "wakeMinuteOfDay")
        XCTAssertTrue(preferences.wakeEnabled)
        XCTAssertEqual(preferences.wakeMinuteOfDay, 390)
        XCTAssertEqual(preferences.helperMinuteOfDay, 390)
    }

    func testMinuteOutOfRangeReadsAsEight() {
        for stored in [-1, 1440, 100_000] {
            defaults.set(stored, forKey: "wakeMinuteOfDay")
            XCTAssertEqual(WakePreferences(defaults: defaults).wakeMinuteOfDay, 480, "\(stored)")
        }
        defaults.set(1439, forKey: "wakeMinuteOfDay")
        XCTAssertEqual(WakePreferences(defaults: defaults).wakeMinuteOfDay, 1439)
    }

    func testSettingIsSaved() {
        preferences.wakeEnabled = true
        preferences.wakeMinuteOfDay = 75
        XCTAssertTrue(defaults.bool(forKey: "wakeEnabled"))
        XCTAssertEqual(defaults.integer(forKey: "wakeMinuteOfDay"), 75)
    }

    // MARK: Agreement with the helper

    func testLaunchWithSettingOnSchedulesTheMinute() async {
        preferences.wakeEnabled = true
        service.wakes = [wakeTime]
        let scheduler = makeScheduler()
        await scheduler.sync()
        XCTAssertEqual(journal.calls, ["set 480", "read"])
        XCTAssertEqual(scheduler.scheduledWakes, [wakeTime])
        XCTAssertNil(scheduler.lastError)
    }

    func testLaunchWithSettingOffCancels() async {
        let scheduler = makeScheduler()
        await scheduler.sync()
        XCTAssertEqual(journal.calls, ["set -1", "read"])
        XCTAssertEqual(scheduler.scheduledWakes, [])
    }

    func testHelperNotReadyMakesNoCall() async {
        helper.ready = false
        preferences.wakeEnabled = true
        let scheduler = makeScheduler()
        await scheduler.sync()
        XCTAssertEqual(journal.calls, [])
        XCTAssertEqual(helper.readyChecks, 1)
        XCTAssertNil(scheduler.lastError)
    }

    func testChangingTheTimeCallsAgain() async {
        _ = makeScheduler()
        preferences.wakeEnabled = true
        await settle { journal.calls.count >= 2 }
        XCTAssertEqual(journal.calls, ["set 480", "read"])

        preferences.wakeMinuteOfDay = 600
        await settle { journal.calls.count >= 4 }
        XCTAssertEqual(journal.calls, ["set 480", "read", "set 600", "read"])

        preferences.wakeEnabled = false
        await settle { journal.calls.count >= 6 }
        XCTAssertEqual(journal.calls, ["set 480", "read", "set 600", "read", "set -1", "read"])
    }

    func testClockOrTimeZoneChangeCallsAgain() async {
        preferences.wakeEnabled = true
        _ = makeScheduler()
        clock.change()
        await settle { journal.calls.count >= 2 }
        XCTAssertEqual(journal.calls, ["set 480", "read"])
        clock.change()
        await settle { journal.calls.count >= 4 }
        XCTAssertEqual(journal.calls, ["set 480", "read", "set 480", "read"])
    }

    func testSystemClockMonitorListensToBothNotifications() {
        let monitor = SystemClockChangeMonitor()
        var count = 0
        monitor.start { count += 1 }
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(count, 2)
    }

    func testErrorIsKeptAndClearedByTheNextCall() async {
        preferences.wakeEnabled = true
        service.wakes = [wakeTime]
        let scheduler = makeScheduler()
        await scheduler.sync()

        service.setError = HelperError.timeout
        await scheduler.sync()
        XCTAssertEqual(scheduler.lastError, HelperError.timeout.localizedDescription)
        XCTAssertEqual(scheduler.scheduledWakes, [wakeTime], "the remembered wakes stay")

        service.setError = nil
        await scheduler.sync()
        XCTAssertNil(scheduler.lastError)
    }

    // MARK: Wake

    func testWakeOnScheduleTurnsTheModeOnBeforeCallingTheHelper() async {
        let scheduler = await scheduledAtWakeTime()
        await wake(scheduler, after: 1)
        XCTAssertEqual(log.events, [.scheduledWake])
        XCTAssertEqual(journal.calls, ["mode", "set 480", "read"])
    }

    func testWakeWindowEdges() async {
        let scheduler = await scheduledAtWakeTime()
        for seconds: TimeInterval in [-10, 0, 120] {
            XCTAssertTrue(scheduler.isScheduledWake(at: wakeTime.addingTimeInterval(seconds)), "\(seconds)")
        }
        for seconds: TimeInterval in [-11, 121] {
            XCTAssertFalse(scheduler.isScheduledWake(at: wakeTime.addingTimeInterval(seconds)), "\(seconds)")
        }
        XCTAssertTrue(scheduler.isScheduledWake(at: wakeTime.addingTimeInterval(86_400 + 5)), "the second wake counts too")
    }

    func testWakeThreeMinutesLateIsAnOrdinaryWake() async {
        let scheduler = await scheduledAtWakeTime()
        await wake(scheduler, after: 180)
        XCTAssertEqual(log.events, [.wake])
        XCTAssertEqual(journal.calls, ["set 480", "read"])
    }

    func testWakeThirtySecondsEarlyIsAnOrdinaryWake() async {
        let scheduler = await scheduledAtWakeTime()
        await wake(scheduler, after: -30)
        XCTAssertEqual(log.events, [.wake])
        XCTAssertEqual(journal.calls, ["set 480", "read"])
    }

    func testWakeWithSettingOffIsAnOrdinaryWake() async {
        let scheduler = await scheduledAtWakeTime()
        preferences.wakeEnabled = false
        await settle { journal.calls.contains("read") }
        journal.calls = []

        await wake(scheduler, after: 0)
        XCTAssertEqual(log.events, [.wake])
        XCTAssertEqual(journal.calls, ["set -1", "read"])
    }

    func testWakeWithoutRememberedTimesIsAnOrdinaryWake() async {
        preferences.wakeEnabled = true
        let scheduler = makeScheduler()
        await wake(scheduler, after: 0)
        XCTAssertEqual(log.events, [.wake])
        XCTAssertEqual(journal.calls, ["set 480", "read"])
    }

    func testRecorderHandsTheWakeToTheScheduler() async {
        let scheduler = await scheduledAtWakeTime()
        let monitor = FakeSleepMonitor()
        let recorder = SystemSleepRecorder(monitor: monitor, log: log, wakeHandler: scheduler)
        recorder.start()

        monitor.change(asleep: true)
        now = wakeTime.addingTimeInterval(1)
        monitor.change(asleep: false)
        await settle { journal.calls.contains("read") }
        XCTAssertEqual(log.events, [.sleep, .scheduledWake], "the wake is recorded once")
        XCTAssertEqual(journal.calls, ["mode", "set 480", "read"])
    }
}
