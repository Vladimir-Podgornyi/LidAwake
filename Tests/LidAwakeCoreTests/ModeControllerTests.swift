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
    var paused = false
    var session: SessionOwnership = .noSession
    var statusError: Error?
    private(set) var calls: [String] = []
    /// The number of other calls made before each status request.
    private(set) var statusRequests: [Int] = []
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
        statusRequests.append(calls.count)
        if let statusError { throw statusError }
        return HelperSessionStatus(
            flag: .unknown,
            session: session,
            timerRemaining: nil,
            power: PowerReading(battery: .unknown, source: .unknown),
            thermal: .unknown,
            paused: paused
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

private final class FakePowerSourceMonitor: PowerSourceMonitoring {
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func change() {
        handler?()
    }
}

private final class FakeLidMonitor: LidMonitoring {
    private var handler: ((Bool) -> Void)?

    func start(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func change(closed: Bool) {
        handler?(closed)
    }
}

private final class FakeScreenLocker: ScreenLocking {
    var isAvailable = true
    private(set) var lockCount = 0

    func lock() {
        lockCount += 1
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
    private let powerMonitor = FakePowerSourceMonitor()
    private let lidMonitor = FakeLidMonitor()
    private let locker = FakeScreenLocker()
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
            powerSourceMonitor: powerMonitor,
            lidMonitor: lidMonitor,
            screenLocker: locker,
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
        XCTAssertEqual(controller.message?.title, "Could not turn on")
    }

    func testLidClosedStartsSession() async throws {
        let controller = makeController()

        try await controller.select(.lidClosed)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(helper.prepareCount, 1)
        XCTAssertEqual(sessions.calls, ["start 120"])
        XCTAssertTrue(activity.isActive)
        XCTAssertNil(controller.message)
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
        XCTAssertEqual(controller.message, .couldNotTurnOn("Install the helper to run with the lid closed."))
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
        XCTAssertEqual(controller.message, .couldNotTurnOn("Could not read SleepDisabled"))
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
        XCTAssertEqual(controller.message, .turnedOffWithError(HelperError.timeout.localizedDescription))
    }

    func testMissingSessionReturnsToOff() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(controller.message, .turnedOffWithError("No active session."))
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
        XCTAssertEqual(sessions.statusRequests, [])
        XCTAssertNil(controller.message)
    }

    func testLaunchStaysOff() async {
        preferences.timerEnabled = true
        let controller = makeController()

        await controller.clearLeftover()
        await settle(until: { false })
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
        XCTAssertEqual(assertion.acquireCount, 0)
        XCTAssertFalse(sessions.calls.contains("start 120"))
        XCTAssertFalse(activity.isActive)
        XCTAssertNil(controller.modeStartedAt)
    }

    func testLaunchEndsSessionOfEarlierRun() async {
        await assertLaunchEndsSession(.ours)
    }

    func testLaunchEndsForeignSessionOfEarlierRun() async {
        await assertLaunchEndsSession(.foreign)
    }

    private func assertLaunchEndsSession(_ session: SessionOwnership) async {
        sessions.session = session
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["end", "reason"])
        XCTAssertEqual(controller.message, .restarted)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(notifier.posts, [])
    }

    func testLaunchWithoutSessionClearsLeftoverQuietly() async {
        sessions.session = .noSession
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(sessions.statusRequests, [0])
        XCTAssertEqual(sessions.calls, ["clear", "reason"])
        XCTAssertNil(controller.message)
        XCTAssertEqual(notifier.posts, [])
    }

    func testLaunchClearsLeftoverWhenStatusFails() async {
        sessions.statusError = HelperError.timeout
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["clear", "reason"])
        XCTAssertNil(controller.message)
    }

    func testStoredReasonWinsOverEndedSession() async {
        sessions.session = .ours
        sessions.stopRecord = StopRecord(reason: .leaseExpired, time: Date())
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["end", "reason", "clear reason"])
        XCTAssertEqual(controller.message, .turnedOff("LidAwake closed unexpectedly, so normal sleep was restored."))
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: LidAwake closed unexpectedly, so normal sleep was restored."])
    }

    func testLaunchLeavesRunningModeAlone() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)
        sessions.session = .ours

        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, ["start 120"])
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertNil(controller.message)
    }

    // MARK: Safety limits and notifications

    func testDefaultPreferences() {
        XCTAssertFalse(preferences.timerEnabled)
        XCTAssertEqual(preferences.timerSeconds, 7200)
        XCTAssertTrue(preferences.batteryLimitEnabled)
        XCTAssertEqual(preferences.batteryLimitPercent, 20)
        XCTAssertTrue(preferences.thermalProtectionEnabled)
        XCTAssertFalse(preferences.chargingOnlyEnabled)
        XCTAssertEqual(
            preferences.helperSettings,
            SafetySettings(timerSeconds: 0, batteryLimitPercent: 20, thermalProtection: true)
        )
    }

    func testPreferencesUseTheirKeys() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "timerEnabled")
        defaults.set(5400, forKey: "timerSeconds")
        defaults.set(false, forKey: "batteryLimitEnabled")
        defaults.set(15, forKey: "batteryLimitPercent")
        defaults.set(false, forKey: "thermalProtectionEnabled")
        defaults.set(true, forKey: "chargingOnlyEnabled")

        let loaded = SafetyPreferences(defaults: defaults)
        XCTAssertEqual(
            loaded.helperSettings,
            SafetySettings(timerSeconds: 5400, batteryLimitPercent: 0, thermalProtection: false, chargingOnly: true)
        )

        loaded.batteryLimitPercent = 40
        XCTAssertEqual(defaults.integer(forKey: "batteryLimitPercent"), 40)
        loaded.thermalProtectionEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "thermalProtectionEnabled"))
        loaded.chargingOnlyEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "chargingOnlyEnabled"))
    }

    func testLidClosedSendsSafetySettings() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 3600
        let controller = makeController()

        try await controller.select(.lidClosed)
        await controller.renew()
        XCTAssertEqual(sessions.safety, [
            SafetySettings(timerSeconds: 3600, batteryLimitPercent: 20, thermalProtection: true),
            SafetySettings(timerSeconds: 3600, batteryLimitPercent: 20, thermalProtection: true),
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
        XCTAssertEqual(controller.message, .turnedOff("The timer ran out."))
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
        XCTAssertEqual(
            sessions.safety.last,
            SafetySettings(timerSeconds: 0, batteryLimitPercent: 30, thermalProtection: true)
        )

        preferences.timerEnabled = true
        await settle { sessions.calls.count >= 3 }
        XCTAssertEqual(
            sessions.safety.last,
            SafetySettings(timerSeconds: 7200, batteryLimitPercent: 30, thermalProtection: true)
        )
    }

    func testThermalSettingChangeSendsRenewal() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        preferences.thermalProtectionEnabled = false
        await settle { sessions.calls.count >= 2 }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])
        XCTAssertEqual(
            sessions.safety.last,
            SafetySettings(timerSeconds: 0, batteryLimitPercent: 20, thermalProtection: false)
        )

        preferences.thermalProtectionEnabled = true
        await settle { sessions.calls.count >= 3 }
        XCTAssertEqual(sessions.safety.last?.thermalProtection, true)
        XCTAssertEqual(controller.mode, .lidClosed)
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
        XCTAssertEqual(controller.message, .turnedOff("The battery dropped to 15%."))
        XCTAssertNil(sessions.stopRecord)
    }

    func testNoSessionAfterThermalStopTurnsOffWithNotification() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.stopRecord = StopRecord(reason: .thermal, time: Date())
        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120", "end", "reason", "clear reason"])
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The Mac got too hot."])
        XCTAssertEqual(controller.message, .turnedOff("The Mac got too hot."))
    }

    func testNoSessionAfterUnreadableThermalStateNotifies() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.stopRecord = StopRecord(reason: .thermalUnreadable, time: Date())
        sessions.renewError = HelperError.helper(.noSession, "No active session.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The thermal state could not be read."])
    }

    func testThermalRefusalShowsError() async {
        sessions.startError = HelperError.helper(.thermalLimitReached, "The Mac is too hot (thermal state serious).")
        let controller = makeController()

        do {
            try await controller.select(.lidClosed)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(activity.isActive)
        XCTAssertEqual(controller.message, .couldNotTurnOn("The Mac is too hot (thermal state serious)."))
        XCTAssertEqual(notifier.posts, [])
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
        XCTAssertEqual(controller.message, .couldNotTurnOn("The battery is at 12%, at or below the 20% limit."))
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
        XCTAssertNil(controller.message)
    }

    func testLaunchShowsUnclearedReasonInWindow() async {
        sessions.stopRecord = StopRecord(reason: .timer, time: Date())
        let controller = makeController()

        await controller.clearLeftover()
        XCTAssertEqual(controller.message, .turnedOff("The timer ran out."))
    }

    func testDismissMessageClearsReason() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 1800
        let controller = makeController()
        try await controller.select(.keepScreenOn)
        time.now += 1800
        await controller.checkTimer()
        XCTAssertEqual(controller.message, .turnedOff("The timer ran out."))

        controller.dismissMessage()
        XCTAssertNil(controller.message)
    }

    func testChoosingModeClearsOldReason() async throws {
        preferences.timerEnabled = true
        preferences.timerSeconds = 1800
        let controller = makeController()
        try await controller.select(.keepScreenOn)
        time.now += 1800
        await controller.checkTimer()
        XCTAssertNotNil(controller.message)

        try await controller.select(.keepScreenOn)
        XCTAssertNil(controller.message)
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
        XCTAssertEqual(StopNotice.body(for: StopRecord(reason: .thermal, time: time)), "The Mac got too hot.")
        XCTAssertEqual(
            StopNotice.body(for: StopRecord(reason: .thermalUnreadable, time: time)),
            "The thermal state could not be read."
        )
        XCTAssertEqual(
            StopNotice.body(for: StopRecord(reason: .powerUnreadable, time: time)),
            "The power source could not be read."
        )
        XCTAssertEqual(PauseNotice.title, "LidAwake paused")
        XCTAssertEqual(PauseNotice.body, "Running on battery. It resumes when you plug in.")
    }

    // MARK: Charging only

    private let pausedNotice = "LidAwake paused: Running on battery. It resumes when you plug in."

    func testPowerSourceChangeSendsRenewalThenAsksForStatus() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertEqual(sessions.statusRequests, [1])

        powerMonitor.change()
        await settle { sessions.statusRequests.count >= 2 }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])
        XCTAssertEqual(sessions.statusRequests, [1, 2])
        XCTAssertEqual(controller.mode, .lidClosed)
    }

    func testPowerSourceChangeOutsideLidClosedSendsNothing() async throws {
        let controller = makeController()
        powerMonitor.change()
        try await controller.select(.keepScreenOn)
        powerMonitor.change()
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(sessions.calls, [])
        XCTAssertEqual(sessions.statusRequests, [])
    }

    func testPauseNotifiesOnce() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(notifier.posts, [])

        sessions.paused = true
        powerMonitor.change()
        await settle { controller.isPaused }
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(notifier.posts, [pausedNotice])

        await controller.renew()
        powerMonitor.change()
        await settle { sessions.statusRequests.count >= 4 }
        XCTAssertEqual(sessions.statusRequests.count, 4)
        XCTAssertEqual(notifier.posts, [pausedNotice])
    }

    func testResumeIsSilent() async throws {
        sessions.paused = true
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(notifier.posts, [pausedNotice])

        sessions.paused = false
        powerMonitor.change()
        await settle { !controller.isPaused }
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(controller.mode, .lidClosed)
        XCTAssertEqual(notifier.posts, [pausedNotice])
        XCTAssertNil(controller.message)
    }

    func testLeavingModeClearsPause() async throws {
        sessions.paused = true
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertTrue(controller.isPaused)

        try await controller.select(.off)
        XCTAssertFalse(controller.isPaused)
    }

    func testChargingOnlySettingChangeSendsRenewal() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertEqual(sessions.safety.last?.chargingOnly, false)

        preferences.chargingOnlyEnabled = true
        await settle { sessions.calls.count >= 2 }
        XCTAssertEqual(sessions.calls, ["start 120", "renew 120"])
        XCTAssertEqual(
            sessions.safety.last,
            SafetySettings(timerSeconds: 0, batteryLimitPercent: 20, thermalProtection: true, chargingOnly: true)
        )
        await settle { sessions.statusRequests.count >= 2 }
        XCTAssertEqual(sessions.statusRequests, [1, 2])
    }

    func testPowerSourceRefusalShowsError() async {
        sessions.startError = HelperError.helper(.powerUnreadable, "The power source could not be read.")
        let controller = makeController()

        do {
            try await controller.select(.lidClosed)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(controller.message, .couldNotTurnOn("The power source could not be read."))
        XCTAssertEqual(notifier.posts, [])
    }

    func testNoSessionAfterUnreadablePowerSourceNotifies() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        sessions.stopRecord = StopRecord(reason: .powerUnreadable, time: Date())
        sessions.renewError = HelperError.helper(.noSession, "The power source could not be read.")
        await controller.renew()
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(notifier.posts, ["LidAwake turned off: The power source could not be read."])
    }

    func testLockSettingDefaultsOnAndSendsNothing() async throws {
        XCTAssertTrue(preferences.lockOnLidCloseEnabled)
        let controller = makeController()
        try await controller.select(.lidClosed)

        preferences.lockOnLidCloseEnabled = false
        XCTAssertFalse(UserDefaults(suiteName: suiteName)!.bool(forKey: "lockOnLidCloseEnabled"))
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(sessions.calls, ["start 120"])
    }

    func testLidCloseLocksInLidClosed() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        lidMonitor.change(closed: true)
        XCTAssertEqual(locker.lockCount, 1)
        XCTAssertEqual(controller.mode, .lidClosed)
    }

    func testLidCloseWithSettingOffDoesNotLock() async throws {
        preferences.lockOnLidCloseEnabled = false
        let controller = makeController()
        try await controller.select(.lidClosed)

        lidMonitor.change(closed: true)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testLidCloseOutsideLidClosedDoesNotLock() async throws {
        let controller = makeController()
        lidMonitor.change(closed: true)
        lidMonitor.change(closed: false)

        try await controller.select(.keepScreenOn)
        lidMonitor.change(closed: true)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testLidCloseLocksWhilePaused() async throws {
        sessions.paused = true
        let controller = makeController()
        try await controller.select(.lidClosed)
        XCTAssertTrue(controller.isPaused)

        lidMonitor.change(closed: true)
        XCTAssertEqual(locker.lockCount, 1)
    }

    func testLidOpenDoesNotLock() async throws {
        let controller = makeController()
        try await controller.select(.lidClosed)

        lidMonitor.change(closed: false)
        XCTAssertEqual(locker.lockCount, 0)
    }

    func testUnavailableLockShowsNotice() async throws {
        locker.isAvailable = false
        let controller = makeController()
        XCTAssertEqual(controller.screenLockNotice, "Screen lock is not available on this macOS version.")

        try await controller.select(.lidClosed)
        lidMonitor.change(closed: true)
        XCTAssertEqual(locker.lockCount, 0)
        XCTAssertEqual(controller.mode, .lidClosed)

        preferences.lockOnLidCloseEnabled = false
        XCTAssertNil(controller.screenLockNotice)
    }

    func testAvailableLockShowsNoNotice() {
        let controller = makeController()
        XCTAssertNil(controller.screenLockNotice)
    }
}
