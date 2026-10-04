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
    private(set) var calls: [String] = []

    func startSession(leaseSeconds: Int) async throws {
        calls.append("start \(leaseSeconds)")
        if let startError { throw startError }
    }

    func renewSession(leaseSeconds: Int) async throws {
        calls.append("renew \(leaseSeconds)")
        if let renewError { throw renewError }
    }

    func endSession() async throws {
        calls.append("end")
    }

    func clearLeftover() async throws {
        calls.append("clear")
    }

    func sessionStatus() async throws -> HelperSessionStatus {
        HelperSessionStatus(flag: .unknown, session: .noSession)
    }
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

    private func makeController() -> ModeController {
        ModeController(
            displayAssertion: assertion,
            helper: helper,
            sessions: sessions,
            activity: activity,
            leaseSeconds: 120,
            renewalSleep: { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
        )
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
        let controller = ModeController(
            displayAssertion: assertion,
            helper: helper,
            sessions: sessions,
            activity: activity,
            leaseSeconds: 120,
            renewalSleep: tick
        )
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
        XCTAssertEqual(sessions.calls, ["clear"])
    }

    func testClearLeftoverSkippedWithoutHelper() async {
        helper.notReady = .notReady("Install the helper to run with the lid closed.")
        let controller = makeController()
        await controller.clearLeftover()
        XCTAssertEqual(sessions.calls, [])
    }
}
