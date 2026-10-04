import LidAwakeShared
import XCTest
@testable import LidAwakeCore

private final class FakeAssertion: PowerAssertion {
    var shouldFail = false
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private(set) var isHeld = false

    func acquire() throws {
        acquireCount += 1
        if shouldFail {
            throw PowerAssertionError(code: -1)
        }
        isHeld = true
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}

@MainActor
private final class FakeHelper: HelperPreparing {
    var notReady: HelperError?
    private(set) var prepareCount = 0

    func prepareForSession() async throws {
        prepareCount += 1
        if let notReady { throw notReady }
    }

    func isReady() async -> Bool {
        notReady == nil
    }
}

private final class FakeSessions: LidSessionService {
    var startError: Error?
    var renewError: Error?
    var stopRecord: StopRecord?
    private(set) var calls: [String] = []
    private(set) var safety: [SafetySettings] = []

    func startSession(leaseSeconds: Int, safety: SafetySettings) async throws {
        calls.append("start \(leaseSeconds)")
        self.safety.append(safety)
        if let startError { throw startError }
    }

    func renewSession(leaseSeconds: Int, safety: SafetySettings) async throws {
        calls.append("renew \(leaseSeconds)")
        self.safety.append(safety)
        if let renewError { throw renewError }
    }

    func endSession() async throws {
        calls.append("end")
    }

    func clearLeftover() async throws {
        calls.append("clear")
    }

    func sessionStatus() async throws -> HelperSessionStatus {
        HelperSessionStatus(
            flag: .unknown,
            session: .noSession,
            timerRemaining: nil,
            power: PowerReading(battery: .unknown, source: .unknown)
        )
    }

    func lastStopReason() async throws -> StopRecord? {
        calls.append("reason")
        return stopRecord
    }

    func clearStopReason() async throws {
        calls.append("clear reason")
        stopRecord = nil
    }
}

@MainActor
private final class FakeNotifier: StopNotifying {
    private(set) var authorizationRequests = 0
    private(set) var posts: [String] = []

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func post(title: String, body: String) {
        posts.append("\(title): \(body)")
    }
}

private final class FakeTime {
    var now: TimeInterval = 1000
}

private final class FakeActivity: ActivityHolding {
    private(set) var isActive = false

    func begin() { isActive = true }
    func end() { isActive = false }
}

@MainActor
final class ModeControllerTests: XCTestCase {
    private let assertion = FakeAssertion()
    private let helper = FakeHelper()
    private let sessions = FakeSessions()
    private let activity = FakeActivity()
    private let notifier = FakeNotifier()
    private let time = FakeTime()
    private let suiteName = "ModeControllerTests-\(UUID().uuidString)"
    private lazy var preferences = SafetyPreferences(defaults: UserDefaults(suiteName: suiteName)!)

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeController(renewalSleep: (() async throws -> Void)? = nil) -> ModeController {
        let time = self.time
        return ModeController(
            displayAssertion: assertion,
            helper: helper,
            sessions: sessions,
            preferences: preferences,
            notifier: notifier,
            activity: activity,
            leaseSeconds: 120,
            renewalSleep: renewalSleep ?? { try await Task.sleep(nanoseconds: 3_600_000_000_000) },
            timerCheckSleep: { try await Task.sleep(nanoseconds: 3_600_000_000_000) },
            now: { time.now }
        )
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() {
            await Task.yield()
        }
    }

    func testStartsOff() {
        let controller = makeController()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
    }

    func testKeepScreenOnAcquiresAndOffReleases() async throws {
        let controller = makeController()

        try await controller.select(.keepScreenOn)
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertTrue(assertion.isHeld)

        try await controller.select(.off)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
    }

    func testRepeatedKeepScreenOnCreatesOneAssertion() async throws {
        let controller = makeController()

        try await controller.select(.keepScreenOn)
        try await controller.select(.keepScreenOn)

        XCTAssertEqual(assertion.acquireCount, 1)
        XCTAssertEqual(controller.mode, .keepScreenOn)
    }

    func testAcquireFailureLeavesModeOff() async {
        assertion.shouldFail = true
        let controller = makeController()

        do {
            try await controller.select(.keepScreenOn)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertNotNil(controller.lastError)
    }

    func testLidClosedStartsSession() async throws {
        let controller = makeController()

        try await controller.select(.lidClosed)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(helper.prepareCount, 1)
        XCTAssertEqual(sessions.calls, ["start 120"])
        XCTAssertTrue(activity.isActive)
        XCTAssertNil(controller.lastError)
    }

    func testLidClosedNeedsReadyHelper() async {
        helper.notReady = .notReady("Install the helper to run with the lid closed.")
        let controller = makeController()

        do {
            try await controller.select(.lidClosed)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(sessions.calls, [])
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(controller.lastError, "Install the helper to run with the lid closed.")
    }

    func testLidClosedStartFailureKeepsKeepScreenOn() async throws {
        sessions.startError = HelperError.helper(.flagReadFailed, "Could not read SleepDisabled")
        let controller = makeController()
        try await controller.select(.keepScreenOn)

        do {
            try await controller.select(.lidClosed)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertTrue(assertion.isHeld)
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(controller.lastError, "Could not read SleepDisabled")
    }

    func testKeepScreenOnToLidClosedReleasesAssertion() async throws {
        let controller = makeController()
        try await controller.select(.keepScreenOn)

        try await controller.select(.lidClosed)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertFalse(assertion.isHeld)
    }

    func testOffEndsSession() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        try await controller.select(.off)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(sessions.calls, ["start 120", "end"])
        XCTAssertFalse(activity.isActive)
    }

    func testKeepScreenOnEndsSession() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        try await controller.select(.keepScreenOn)
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertEqual(sessions.calls, ["start 120", "end"])
        XCTAssertTrue(assertion.isHeld)
        XCTAssertFalse(activity.isActive)
    }

    func testRenewKeepsMode() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        await controller.renew()
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])
    }

    func testRenewFailureReturnsToOff() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.renewError = HelperError.timeout
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120", "end"])
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(controller.lastError, HelperError.timeout.localizedDescription)
    }

    func testMissingSessionReturnsToOff() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(controller.lastError, "No active session.")
    }

    func testRenewalsRunOnSchedule() async throws {
        let ticks = AsyncStream<Void>.makeStream()
        var iterator = ticks.stream.makeAsyncIterator()
        let tick = { () async throws -> Void in
            _ = await iterator.next()
            try Task.checkCancellation()
        }
        let controller = makeController(renewalSleep: tick)
        try await controller.select(.lidClosed)

        ticks.continuation.yield()
        for _ in 0..<100 where sessions.calls.count < 2 {
            await Task.yield()
        }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])

        try await controller.select(.off)
        ticks.continuation.yield()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120", "end"])
    }

    func testClearLeftoverWhenHelperReady() async {
        let controller = makeController()
        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["clear", "reason"])
    }

    func testClearLeftoverSkippedWithoutHelper() async {
        helper.notReady = .notReady("Install the helper to run with the lid closed.")
        let controller = makeController()
        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, [])
    }

    // MARK: Safety limits and notifications

    func testDefaultPreferences() {
        XCTAssertFalse(preferences.timerEnabled)
        XCTAssertEqual(preferences.timerSeconds, 7200)
        XCTAssertTrue(preferences.batteryLimitEnabled)
        XCTAssertEqual(preferences.batteryLimitPercent, 20)
        XCTAssertEqual(preferences.helperSettings, SafetySettings(timerSeconds: 0, batteryLimitPercent: 20))
    }

    func testPreferencesUseTheirKeys() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "timerEnabled")
        defaults.set(5400, forKey: "timerSeconds")
        defaults.set(false, forKey: "batteryLimitEnabled")
        defaults.set(15, forKey: "batteryLimitPercent")

        let loaded = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(loaded.helperSettings, SafetySettings(timerSeconds: 5400, batteryLimitPercent: 0))

        loaded.batteryLimitPercent = 40
        XCTAssertEqual(defaults.integer(forKey: "batteryLimitPercent"), 40)
    }

    func testLidClosedSendsSafetySettings() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 3600
        let controller = makeController()

        try await controller.select(.lidClosed)
        await controller.renew()
        XCTAssertEqual(sessions.safety, [
            SafetySettings(timerSeconds: 3600, batteryLimitPercent: 20),
            SafetySettings(timerSeconds: 3600, batteryLimitPercent: 20),
        ])
    }

    func testKeepScreenOnTimerTurnsOff() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 3600
        let controller = makeController()
        try await controller.select(.keepScreenOn)
        XCTAssertEqual(controller.timerRemaining(), 3600)

        time.now += 3599
        await controller.checkTimer()
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertEqual(controller.timerRemaining(), 1)

        time.now += 1
        await controller.checkTimer()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertNil(controller.timerRemaining())
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The timer ran out."])
        XCTAssertEqual(controller.lastError, "The timer ran out.")
        XCTAssertEqual(sessions.calls, [])
    }

    func testKeepScreenOnIgnoresBatteryLimit() async throws {
        preferences.batteryLimitPercent = 50
        let controller = makeController()
        try await controller.select(.keepScreenOn)

        time.now += 100_000
        await controller.checkTimer()
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertNil(controller.timerRemaining())
        XCTAssertEqual(sessions.calls, [])
    }

    func testKeepScreenOnTimerChangeCountsFromStart() async throws {
        preferences.timerEnabled = true
        let controller = makeController()
        try await controller.select(.keepScreenOn)

        time.now += 2000
        preferences.timerSeconds = 1800
        await settle { controller.mode == .off }
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The timer ran out."])
    }

    func testSettingChangeSendsRenewal() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        preferences.batteryLimitPercent = 30
        await settle { sessions.calls.count >= 2 }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])
        XCTAssertEqual(sessions.safety.last, SafetySettings(timerSeconds: 0, batteryLimitPercent: 30))

        preferences.timerEnabled = true
        await settle { sessions.calls.count >= 3 }
        XCTAssertEqual(sessions.safety.last, SafetySettings(timerSeconds: 7200, batteryLimitPercent: 30))
    }

    func testSettingChangeWhileOffSendsNothing() async {
        _ = makeController()
        preferences.batteryLimitPercent = 30
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(sessions.calls, [])
    }

    func testNoSessionTurnsOffWithNotification() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.stopRecord = StopRecord(reason: .battery, time: Date(), batteryPercent: 15)
        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120", "end", "reason", "clear reason"])
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The battery dropped to 15%."])
        XCTAssertEqual(controller.lastError, "The battery dropped to 15%.")
        XCTAssertNil(sessions.stopRecord)
    }

    func testLidClosedTimerAsksHelperEarly() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 1800
        let controller = makeController()
        try await controller.select(.lidClosed)

        time.now += 1799
        await controller.checkTimer()
        XCTAssertEqual(sessions.calls, ["start 120"])

        time.now += 1
        sessions.stopRecord = StopRecord(reason: .timer, time: Date())
        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.checkTimer()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The timer ran out."])
    }

    func testBatteryRefusalShowsError() async {
        sessions.startError = HelperError.helper(.batteryLimitReached, "The battery is at 12%, at or below the 20% limit.")
        let controller = makeController()

        do {
            try await controller.select(.lidClosed)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(controller.lastError, "The battery is at 12%, at or below the 20% limit.")
        XCTAssertEqual(notifier.posts, [])
    }

    func testLaunchReportsUnclearedReason() async {
        sessions.stopRecord = StopRecord(reason: .leaseExpired, time: Date())
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["clear", "reason", "clear reason"])
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: LidAwake closed unexpectedly, so normal sleep was restored."])
        XCTAssertNil(sessions.stopRecord)
    }

    func testLaunchWithoutReasonStaysQuiet() async {
        let controller = makeController()
        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["clear", "reason"])
        XCTAssertEqual(notifier.posts, [])
        XCTAssertNil(controller.lastError)
    }

    func testAuthorizationRequestedOnFirstMode() async throws {
        let controller = makeController()
        try await controller.select(.off)
        XCTAssertEqual(notifier.authorizationRequests, 0)

        try await controller.select(.keepScreenOn)
        try await controller.select(.lidClosed)
        try await controller.select(.off)
        try await controller.select(.keepScreenOn)
        XCTAssertEqual(notifier.authorizationRequests, 1)
    }

    func testNoticeTexts() {
        let time = Date()
        XCTAssertEqual(StopNotice.title, "LidAwake turned off")
        XCTAssertEqual(StopNotice.body(for: StopRecord(reason: .timer, time: time)), "The timer ran out.")
        XCTAssertEqual(
            StopNotice.body(for: StopRecord(reason: .battery, time: time, batteryPercent: 9)),
            "The battery dropped to 9%."
        )
        XCTAssertEqual(
            StopNotice.body(for: StopRecord(reason: .batteryUnreadable, time: time)),
            "The battery level could not be read."
        )
        XCTAssertEqual(
            StopNotice.body(for: StopRecord(reason: .leaseExpired, time: time)),
            "LidAwake closed unexpectedly, so normal sleep was restored."
        )
    }
}
