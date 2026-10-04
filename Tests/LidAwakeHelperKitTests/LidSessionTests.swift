import LidAwakeShared
import XCTest
@testable import LidAwakeHelperKit

private struct FakeError: Error {}

private final class FakeFlag: SleepFlag {
    var value: Bool
    var readFails = false
    var writeFails = false
    private(set) var writes: [Bool] = []

    init(_ value: Bool) {
        self.value = value
    }

    func read() throws -> Bool {
        if readFails { throw FakeError() }
        return value
    }

    func write(_ newValue: Bool) throws {
        writes.append(newValue)
        if writeFails { throw FakeError() }
        value = newValue
    }
}

private final class FakeMarker: OwnershipMarker {
    var isSet: Bool
    var onSet: (() -> Void)?

    init(_ isSet: Bool = false) {
        self.isSet = isSet
    }

    func set() throws {
        onSet?()
        isSet = true
    }
    func clear() throws { isSet = false }
}

private final class FakeClock: SessionClock {
    var now: TimeInterval = 1000
}

private final class FakePower: PowerSourceReading {
    var reading = PowerReading(battery: .percent(80), source: .ac)
    private(set) var readCount = 0

    func read() -> PowerReading {
        readCount += 1
        return reading
    }
}

private final class FakeThermal: ThermalStateReading {
    var state = ThermalState.nominal
    private(set) var readCount = 0

    func read() -> ThermalState {
        readCount += 1
        return state
    }
}

private final class FakeStopReasons: StopReasonStore {
    var record: StopRecord?

    func read() -> StopRecord? { record }
    func write(_ record: StopRecord) throws { self.record = record }
    func clear() throws { record = nil }
}

final class LidSessionTests: XCTestCase {
    private var flag = FakeFlag(false)
    private var marker = FakeMarker()
    private let clock = FakeClock()
    private let awakeClock = FakeClock()
    private let power = FakePower()
    private let thermal = FakeThermal()
    private let stopReasons = FakeStopReasons()
    private let wallTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let noLimits = SafetySettings.off

    // Both clocks move together while the Mac is awake.
    private func advance(_ seconds: TimeInterval) {
        clock.now += seconds
        awakeClock.now += seconds
    }

    private func makeSession() -> LidSession {
        LidSession(
            flag: flag,
            marker: marker,
            clock: clock,
            awakeClock: awakeClock,
            power: power,
            thermal: thermal,
            stopReasons: stopReasons,
            wallClock: { [wallTime] in wallTime }
        )
    }

    func testOwnSessionSetsAndClearsFlag() {
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertEqual(session.status().flag, .on)
        XCTAssertEqual(session.status().session, .ours)

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.status().flag, .off)
        XCTAssertEqual(session.status().session, .noSession)
    }

    func testForeignFlagIsNeverTouched() {
        flag = FakeFlag(true)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(session.status().session, .foreign)

        XCTAssertEqual(session.end(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
        XCTAssertFalse(session.isActive)
    }

    func testReadFailureRefusesAndChangesNothing() {
        flag.readFails = true
        let session = makeSession()

        let result = session.start(lease: 120, safety: noLimits)
        XCTAssertEqual(result.code, .flagReadFailed)
        XCTAssertNotNil(result.message)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
        XCTAssertEqual(session.status().flag, .unknown)
    }

    func testWriteFailureOnStartLeavesNoSession() {
        flag.writeFails = true
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: noLimits).code, .flagWriteFailed)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
    }

    func testLeftoverMarkerWithFlagSetCountsAsOurs() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testRenewMovesDeadline() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        advance(100)
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        advance(100)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(flag.value)

        advance(20)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
    }

    func testRenewWithoutSession() {
        let session = makeSession()
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits).code, .noSession)
        XCTAssertEqual(flag.writes, [])
    }

    func testRenewRestoresClearedFlag() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [true, true])
    }

    func testRenewKeepsForeignSessionWhileFlagIsSet() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertFalse(marker.isSet)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testRenewTakesOverForeignSessionWhenFlagIsGone() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertTrue(marker.isSet)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [true])
        XCTAssertEqual(session.status().session, .ours)

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [true, false])
    }

    func testTakeOverSetsMarkerBeforeFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.value = false
        flag.writeFails = true
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits).code, .flagWriteFailed)
        XCTAssertEqual(session.ownership, .foreign)
        // The marker was written first and stays because the flag could not be cleared either.
        XCTAssertTrue(marker.isSet)
    }

    func testRenewReportsReadFailureForForeignSession() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.readFails = true
        let result = session.renew(lease: 120, safety: noLimits)
        XCTAssertEqual(result.code, .flagReadFailed)
        XCTAssertNotNil(result.message)
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
    }

    func testRenewReportsRestoreFailure() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.value = false
        flag.writeFails = true
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits).code, .flagWriteFailed)
    }

    func testExpiredLeaseEndsOwnSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        advance(119)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(flag.value)

        advance(1)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testExpiredLeaseKeepsForeignFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        advance(120)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testClearLeftoverWithMarker() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        let session = makeSession()

        XCTAssertEqual(session.clearLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testClearLeftoverWithoutMarker() {
        flag = FakeFlag(true)
        let session = makeSession()

        XCTAssertEqual(session.clearLeftover(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testClearLeftoverKeepsActiveSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        XCTAssertEqual(session.clearLeftover(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(session.isActive)
    }

    func testClearLeftoverKeepsMarkerWhenWriteFails() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        flag.writeFails = true
        let session = makeSession()

        XCTAssertEqual(session.clearLeftover().code, .flagWriteFailed)
        XCTAssertTrue(marker.isSet)
    }

    func testLaunchClearsLeftover() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        let session = makeSession()

        XCTAssertEqual(session.retryLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(session.needsHelper)
    }

    func testLaunchWithoutMarkerChangesNothing() {
        flag = FakeFlag(true)
        let session = makeSession()

        XCTAssertNil(session.retryLeftover())
        XCTAssertTrue(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
        XCTAssertFalse(session.needsHelper)
    }

    func testFailedLeftoverCleanupRetriesEveryThirtySeconds() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        flag.writeFails = true
        let session = makeSession()

        XCTAssertEqual(session.retryLeftover()?.code, .flagWriteFailed)
        XCTAssertEqual(flag.writes, [false])
        XCTAssertTrue(session.needsHelper)

        advance(29)
        XCTAssertNil(session.retryLeftover())
        XCTAssertEqual(flag.writes, [false])
        XCTAssertTrue(session.needsHelper)

        advance(1)
        XCTAssertEqual(session.retryLeftover()?.code, .flagWriteFailed)
        XCTAssertEqual(flag.writes, [false, false])
        XCTAssertTrue(marker.isSet)
        XCTAssertTrue(session.needsHelper)

        flag.writeFails = false
        advance(30)
        XCTAssertEqual(session.retryLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(session.needsHelper)
    }

    func testLeftoverRetryLeavesActiveSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        XCTAssertNil(session.retryLeftover())
        XCTAssertTrue(flag.value)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.needsHelper)
    }

    func testEndWithoutSessionClearsLeftover() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        let session = makeSession()

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testMarkerSurvivesRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LidSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = LidSession(
            flag: flag,
            marker: FileOwnershipMarker(directory: directory),
            clock: clock,
            awakeClock: awakeClock,
            power: power,
            thermal: thermal,
            stopReasons: stopReasons
        )
        XCTAssertEqual(first.start(lease: 120, safety: noLimits), .ok)
        XCTAssertTrue(flag.value)

        let fileMarker = FileOwnershipMarker(directory: directory)
        XCTAssertTrue(fileMarker.isSet)
        let second = LidSession(
            flag: flag,
            marker: fileMarker,
            clock: clock,
            awakeClock: awakeClock,
            power: power,
            thermal: thermal,
            stopReasons: stopReasons
        )
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(second.clearLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(FileOwnershipMarker(directory: directory).isSet)
    }

    // MARK: Safety limits

    private func limits(timer: Int = 0, battery: Int = 0, thermal: Bool = false) -> SafetySettings {
        SafetySettings(timerSeconds: timer, batteryLimitPercent: battery, thermalProtection: thermal)
    }

    func testTimerEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 3600)), .ok)

        for _ in 0..<35 {
            advance(100)
            XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 3600)), .ok)
            XCTAssertNil(session.enforceLimits())
        }
        XCTAssertEqual(session.status().timerRemaining, 100)

        advance(100)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .timer, time: wallTime))
    }

    func testTimerChangeCountsFromSessionStart() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 7200)), .ok)

        advance(100)
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 3600)), .ok)
        XCTAssertEqual(session.status().timerRemaining, 3500)

        advance(100)
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 300)), .ok)
        XCTAssertEqual(session.status().timerRemaining, 100)

        advance(99)
        XCTAssertNil(session.enforceLimits())
        advance(1)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testShorterTimerPastElapsedTimeEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 7200)), .ok)

        advance(200)
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 180)), .ok)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testTimerOffNeverEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 3600)), .ok)
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)

        advance(100)
        XCTAssertNil(session.status().timerRemaining)
        XCTAssertNil(session.enforceLimits())
    }

    func testBatteryAtLimitOnBatteryEndsSession() {
        power.reading = PowerReading(battery: .percent(25), source: .battery)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)), .ok)
        XCTAssertNil(session.enforceLimits())

        power.reading = PowerReading(battery: .percent(20), source: .battery)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .battery, time: wallTime, batteryPercent: 20))
    }

    func testBatteryAtLimitOnACKeepsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)), .ok)

        power.reading = PowerReading(battery: .percent(5), source: .ac)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(flag.value)
        XCTAssertNil(stopReasons.record)
    }

    func testBatteryLimitOffKeepsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        power.reading = PowerReading(battery: .unknown, source: .unknown)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
    }

    func testUnreadableBatteryEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)), .ok)

        power.reading = PowerReading(battery: .unknown, source: .unknown)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .batteryUnreadable, time: wallTime))
    }

    func testUnknownPowerSourceCountsAsUnreadable() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)), .ok)

        power.reading = PowerReading(battery: .percent(90), source: .unknown)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .batteryUnreadable)
    }

    func testMacWithoutBatteryIgnoresLimit() {
        power.reading = PowerReading(battery: .none, source: .ac)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 100)), .ok)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.status().power, PowerReading(battery: .none, source: .ac))
    }

    func testStartRefusedAtBatteryLimit() {
        power.reading = PowerReading(battery: .percent(20), source: .battery)
        let session = makeSession()

        let result = session.start(lease: 120, safety: limits(battery: 20))
        XCTAssertEqual(result.code, .batteryLimitReached)
        XCTAssertNotNil(result.message)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
        XCTAssertNil(stopReasons.record)
    }

    func testStartRefusedWhenBatteryUnreadable() {
        power.reading = PowerReading(battery: .unknown, source: .unknown)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)).code, .batteryLimitReached)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
    }

    func testStartAllowedAboveLimitAndOnAC() {
        power.reading = PowerReading(battery: .percent(21), source: .battery)
        XCTAssertEqual(makeSession().start(lease: 120, safety: limits(battery: 20)), .ok)

        flag = FakeFlag(false)
        marker = FakeMarker()
        power.reading = PowerReading(battery: .percent(5), source: .ac)
        XCTAssertEqual(makeSession().start(lease: 120, safety: limits(battery: 20)), .ok)
    }

    func testLimitsEndForeignSessionWithoutTouchingFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 60, battery: 20)), .ok)
        XCTAssertEqual(session.ownership, .foreign)

        power.reading = PowerReading(battery: .percent(10), source: .battery)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
        XCTAssertEqual(stopReasons.record?.reason, .battery)

        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 60)), .ok)
        advance(60)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testExpiredLeaseRecordsReason() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        advance(120)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .leaseExpired, time: wallTime))
    }

    func testEndRequestedByAppRecordsNoReason() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 60, battery: 20)), .ok)
        XCTAssertEqual(session.end(), .ok)
        XCTAssertNil(stopReasons.record)
        XCTAssertNil(session.lastStopReason())
    }

    func testStopReasonSurvivesRecreationAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LidSessionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let make = {
            LidSession(
                flag: self.flag,
                marker: self.marker,
                clock: self.clock,
            awakeClock: self.awakeClock,
                power: self.power,
                thermal: self.thermal,
                stopReasons: FileStopReasonStore(directory: directory),
                wallClock: { [wallTime = self.wallTime] in wallTime }
            )
        }

        let first = make()
        XCTAssertNil(first.lastStopReason())
        XCTAssertEqual(first.start(lease: 120, safety: limits(battery: 30)), .ok)
        power.reading = PowerReading(battery: .percent(30), source: .battery)
        XCTAssertEqual(first.enforceLimits(), .ok)

        let second = make()
        XCTAssertEqual(second.lastStopReason(), StopRecord(reason: .battery, time: wallTime, batteryPercent: 30))
        XCTAssertEqual(second.clearStopReason(), .ok)
        XCTAssertNil(second.lastStopReason())
        XCTAssertNil(make().lastStopReason())
        XCTAssertEqual(second.clearStopReason(), .ok)
    }

    func testInvalidSafetySettingsAreRefused() {
        let invalid = [
            limits(timer: -1),
            limits(timer: 59),
            limits(timer: 86_401),
            limits(battery: -1),
            limits(battery: 101),
        ]
        let session = makeSession()
        for settings in invalid {
            XCTAssertEqual(session.start(lease: 120, safety: settings).code, .invalidArgument, "\(settings)")
        }
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(flag.writes, [])
        XCTAssertFalse(marker.isSet)

        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 60, battery: 1)), .ok)
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 86_400, battery: 100)), .ok)
        for settings in invalid {
            XCTAssertEqual(session.renew(lease: 120, safety: settings).code, .invalidArgument, "\(settings)")
        }
        XCTAssertEqual(session.safety, limits(timer: 86_400, battery: 100))
    }

    func testStatusReportsTimerAndPower() {
        power.reading = PowerReading(battery: .percent(82), source: .battery)
        let session = makeSession()
        XCTAssertNil(session.status().timerRemaining)
        XCTAssertEqual(session.status().power, PowerReading(battery: .percent(82), source: .battery))

        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 3600)), .ok)
        advance(0.5)
        XCTAssertEqual(session.status().timerRemaining, 3600)
        advance(99.5)
        XCTAssertEqual(session.status().timerRemaining, 3500)
    }

    // MARK: Thermal protection

    func testSeriousAndCriticalEndSession() {
        for state in [ThermalState.serious, .critical] {
            flag = FakeFlag(false)
            marker = FakeMarker()
            thermal.state = .nominal
            let session = makeSession()
            XCTAssertEqual(session.start(lease: 120, safety: limits(thermal: true)), .ok)

            thermal.state = state
            XCTAssertEqual(session.enforceLimits(), .ok, "\(state)")
            XCTAssertFalse(session.isActive)
            XCTAssertFalse(flag.value)
            XCTAssertFalse(marker.isSet)
            XCTAssertEqual(stopReasons.record, StopRecord(reason: .thermal, time: wallTime))
        }
    }

    func testNominalAndFairKeepSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(thermal: true)), .ok)

        for state in [ThermalState.nominal, .fair] {
            thermal.state = state
            XCTAssertNil(session.enforceLimits(), "\(state)")
            XCTAssertTrue(session.isActive)
            XCTAssertTrue(flag.value)
        }
        XCTAssertNil(stopReasons.record)
    }

    func testThermalProtectionOffKeepsSessionWhenCritical() {
        thermal.state = .critical
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(thermal: false)), .ok)

        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(flag.value)

        thermal.state = .unknown
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertNil(stopReasons.record)
    }

    func testUnreadableThermalStateEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(thermal: true)), .ok)

        thermal.state = .unknown
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .thermalUnreadable, time: wallTime))
    }

    func testUnrecognizedSystemValueIsUnknown() {
        XCTAssertEqual(ThermalState(.nominal), .nominal)
        XCTAssertEqual(ThermalState(.fair), .fair)
        XCTAssertEqual(ThermalState(.serious), .serious)
        XCTAssertEqual(ThermalState(.critical), .critical)
        XCTAssertEqual(ThermalState(ProcessInfo.ThermalState(rawValue: 42)!), .unknown)
    }

    func testStartRefusedWhenHot() {
        for state in [ThermalState.serious, .critical, .unknown] {
            thermal.state = state
            let session = makeSession()

            let result = session.start(lease: 120, safety: limits(thermal: true))
            XCTAssertEqual(result.code, .thermalLimitReached, "\(state)")
            XCTAssertNotNil(result.message)
            XCTAssertFalse(session.isActive)
            XCTAssertFalse(marker.isSet)
            XCTAssertEqual(flag.writes, [])
            XCTAssertNil(stopReasons.record)
        }

        thermal.state = .critical
        XCTAssertEqual(makeSession().start(lease: 120, safety: limits(thermal: false)), .ok)
    }

    func testThermalProtectionEndsForeignSessionWithoutTouchingFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(thermal: true)), .ok)
        XCTAssertEqual(session.ownership, .foreign)

        thermal.state = .serious
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(stopReasons.record?.reason, .thermal)
    }

    func testRenewTurnsThermalProtectionOn() {
        thermal.state = .serious
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)
        XCTAssertNil(session.enforceLimits())

        XCTAssertEqual(session.renew(lease: 120, safety: limits(thermal: true)), .ok)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .thermal)
    }

    func testLimitsAreCheckedTimerThermalBatteryLease() {
        let all = limits(timer: 60, battery: 20, thermal: true)
        let tripped = {
            self.thermal.state = .critical
            self.power.reading = PowerReading(battery: .percent(5), source: .battery)
        }
        let reset = {
            self.flag = FakeFlag(false)
            self.marker = FakeMarker()
            self.thermal.state = .nominal
            self.power.reading = PowerReading(battery: .percent(80), source: .ac)
        }

        reset()
        var session = makeSession()
        XCTAssertEqual(session.start(lease: 60, safety: all), .ok)
        advance(60)
        tripped()
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)

        reset()
        session = makeSession()
        XCTAssertEqual(session.start(lease: 60, safety: all), .ok)
        advance(59)
        tripped()
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .thermal)

        reset()
        session = makeSession()
        XCTAssertEqual(session.start(lease: 30, safety: all), .ok)
        advance(30)
        power.reading = PowerReading(battery: .percent(5), source: .battery)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .battery)

        reset()
        session = makeSession()
        XCTAssertEqual(session.start(lease: 30, safety: all), .ok)
        advance(30)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .leaseExpired)
    }

    func testStartChecksThermalBeforeBattery() {
        thermal.state = .serious
        power.reading = PowerReading(battery: .percent(5), source: .battery)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20, thermal: true)).code, .thermalLimitReached)
        XCTAssertEqual(session.start(lease: 120, safety: limits(battery: 20)).code, .batteryLimitReached)
    }

    func testStatusReportsThermalState() {
        thermal.state = .fair
        let session = makeSession()
        XCTAssertEqual(session.status().thermal, .fair)

        thermal.state = .unknown
        XCTAssertEqual(session.status().thermal, .unknown)
    }

    // MARK: Charging only

    private let onAC = PowerReading(battery: .percent(80), source: .ac)
    private let onBattery = PowerReading(battery: .percent(80), source: .battery)

    private func chargingOnly(timer: Int = 0, battery: Int = 0, thermal: Bool = false) -> SafetySettings {
        SafetySettings(timerSeconds: timer, batteryLimitPercent: battery, thermalProtection: thermal, chargingOnly: true)
    }

    func testBatteryPowerPausesOwnSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertFalse(session.isPaused)

        power.reading = onBattery
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [true, false])
        XCTAssertEqual(session.status().paused, true)
        XCTAssertEqual(session.status().session, .ours)
        XCTAssertNil(stopReasons.record)

        XCTAssertNil(session.enforceLimits())
        XCTAssertEqual(flag.writes, [true, false])
    }

    func testACPowerResumesOwnSessionMarkerBeforeFlag() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        var writesWhenMarkerSet: [Bool]?
        marker.onSet = { [flag] in writesWhenMarkerSet = flag.writes }

        power.reading = onAC
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(writesWhenMarkerSet, [])
        XCTAssertEqual(flag.writes, [true])
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.status().paused, false)

        XCTAssertNil(session.enforceLimits())
        XCTAssertEqual(flag.writes, [true])
    }

    func testRenewPausesAndResumes() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = onBattery
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)

        power.reading = onAC
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
        XCTAssertEqual(flag.writes, [true, false, true])
    }

    func testStartOnBatteryBeginsPaused() {
        power.reading = onBattery
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
        XCTAssertEqual(session.status().paused, true)
    }

    func testStartOnBatteryReleasesOwnLeftover() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        power.reading = onBattery
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testChargingOnlyOffNeverPauses() {
        power.reading = onBattery
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertNil(session.enforceLimits())
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(flag.value)

        power.reading = PowerReading(battery: .percent(80), source: .unknown)
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.status().paused, false)
    }

    func testRenewWithChargingOnlyOffResumes() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertTrue(session.isPaused)

        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
    }

    func testMacWithoutBatteryNeverPauses() {
        for source in [PowerSource.ac, .battery, .unknown] {
            flag = FakeFlag(false)
            marker = FakeMarker()
            power.reading = PowerReading(battery: .none, source: source)
            let session = makeSession()

            XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok, "\(source)")
            XCTAssertFalse(session.isPaused)
            XCTAssertNil(session.enforceLimits())
            XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
            XCTAssertTrue(session.isActive)
            XCTAssertFalse(session.isPaused)
            XCTAssertTrue(flag.value)
        }
    }

    func testUnreadablePowerSourceRefusesStart() {
        power.reading = PowerReading(battery: .percent(80), source: .unknown)
        let session = makeSession()

        let result = session.start(lease: 120, safety: chargingOnly())
        XCTAssertEqual(result, SessionResult(code: .powerUnreadable, message: "The power source could not be read."))
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
        XCTAssertNil(stopReasons.record)
    }

    func testUnreadablePowerSourceEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = PowerReading(battery: .percent(80), source: .unknown)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .powerUnreadable, time: wallTime))
    }

    func testUnreadablePowerSourceOnRenewEndsSession() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = PowerReading(battery: .percent(80), source: .unknown)
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()).code, .noSession)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(flag.writes, [])
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(stopReasons.record?.reason, .powerUnreadable)
    }

    func testRenewWhilePausedLeavesFlagOff() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        for _ in 0..<3 {
            advance(30)
            XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
            XCTAssertNil(session.enforceLimits())
        }
        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])
    }

    func testPausedForeignSessionKeepsFlagAndOwnership() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertEqual(session.ownership, .foreign)

        power.reading = onBattery
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertTrue(session.isPaused)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(session.status().session, .foreign)
        XCTAssertEqual(session.status().paused, true)

        // The other program releases its flag while LidAwake is paused.
        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertNil(session.enforceLimits())
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testStartOnBatteryWithForeignFlagIsPausedForeign() {
        flag = FakeFlag(true)
        power.reading = onBattery
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.end(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testResumedForeignSessionFollowsUsualRules() {
        flag = FakeFlag(true)
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = onAC
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.ownership, .foreign)
        XCTAssertEqual(flag.writes, [])

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertTrue(marker.isSet)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [true])
    }

    func testResumeWithForeignFlagBecomesForeign() {
        for viaRenew in [false, true] {
            flag = FakeFlag(false)
            marker = FakeMarker()
            power.reading = onBattery
            let session = makeSession()
            XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
            XCTAssertEqual(session.ownership, .ours)

            // Another program sets the flag during the pause.
            flag.value = true
            var markerSet = false
            marker.onSet = { markerSet = true }
            power.reading = onAC
            if viaRenew {
                XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
            } else {
                XCTAssertEqual(session.enforceLimits(), .ok)
            }
            XCTAssertFalse(session.isPaused, "renew: \(viaRenew)")
            XCTAssertEqual(session.ownership, .foreign)
            XCTAssertEqual(session.status().session, .foreign)
            XCTAssertFalse(markerSet)
            XCTAssertFalse(marker.isSet)
            XCTAssertEqual(flag.writes, [])

            XCTAssertEqual(session.end(), .ok)
            XCTAssertTrue(flag.value)
            XCTAssertEqual(flag.writes, [])
            XCTAssertFalse(marker.isSet)
        }
    }

    func testResumeFlagReadFailureStaysPaused() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = onAC
        flag.readFails = true
        XCTAssertEqual(session.enforceLimits()?.code, .flagReadFailed)
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()).code, .flagReadFailed)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(flag.writes, [])

        flag.readFails = false
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
    }

    func testForeignAfterResumeTakesOverWhenFlagDisappears() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        flag.value = true
        power.reading = onAC
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(session.ownership, .foreign)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()), .ok)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertTrue(marker.isSet)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [true])

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testPauseFailureKeepsSessionRunning() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = onBattery
        flag.writeFails = true
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()).code, .flagWriteFailed)
        XCTAssertEqual(session.enforceLimits()?.code, .flagWriteFailed)
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(marker.isSet)

        flag.writeFails = false
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertTrue(session.isPaused)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testResumeFailureStaysPaused() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        power.reading = onAC
        flag.writeFails = true
        XCTAssertEqual(session.renew(lease: 120, safety: chargingOnly()).code, .flagWriteFailed)
        XCTAssertTrue(session.isPaused)

        flag.writeFails = false
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isPaused)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
    }

    func testLimitsTripWhilePaused() {
        let cases: [(SafetySettings, () -> Void, StopReason)] = [
            (chargingOnly(timer: 60), { self.advance(60) }, .timer),
            (chargingOnly(thermal: true), { self.thermal.state = .serious }, .thermal),
            (chargingOnly(battery: 20), {
                self.power.reading = PowerReading(battery: .percent(20), source: .battery)
            }, .battery),
        ]
        for (settings, trip, reason) in cases {
            flag = FakeFlag(false)
            marker = FakeMarker()
            thermal.state = .nominal
            power.reading = onBattery
            stopReasons.record = nil
            let session = makeSession()
            XCTAssertEqual(session.start(lease: 120, safety: settings), .ok)
            XCTAssertTrue(session.isPaused)

            trip()
            XCTAssertEqual(session.enforceLimits(), .ok, "\(reason)")
            XCTAssertFalse(session.isActive)
            XCTAssertFalse(session.isPaused)
            XCTAssertEqual(stopReasons.record?.reason, reason)
            XCTAssertEqual(flag.writes, [])
            XCTAssertFalse(marker.isSet)
        }
    }

    func testLimitsAreCheckedBatteryPowerSourceLease() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 30, safety: chargingOnly(battery: 20)), .ok)
        advance(30)
        power.reading = PowerReading(battery: .unknown, source: .unknown)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .batteryUnreadable)

        power.reading = onAC
        XCTAssertEqual(session.start(lease: 30, safety: chargingOnly()), .ok)
        advance(30)
        power.reading = PowerReading(battery: .percent(80), source: .unknown)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .powerUnreadable)

        power.reading = onAC
        XCTAssertEqual(session.start(lease: 30, safety: chargingOnly()), .ok)
        advance(30)
        power.reading = onBattery
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .leaseExpired)
    }

    func testLeaseCountsOnlyAwakeTime() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)

        // Three hours asleep: the awake clock stands still.
        clock.now += 10_800
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.isPaused)

        awakeClock.now += 119
        XCTAssertNil(session.enforceLimits())
        awakeClock.now += 1
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(stopReasons.record?.reason, .leaseExpired)
    }

    func testRenewMovesLeaseOnAwakeClock() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        awakeClock.now += 100
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        awakeClock.now += 119
        XCTAssertNil(session.enforceLimits())
        awakeClock.now += 1
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .leaseExpired)
    }

    func testTimerCountsTimeAsleep() {
        power.reading = onBattery
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly(timer: 3600)), .ok)

        clock.now += 3599
        XCTAssertNil(session.enforceLimits())
        XCTAssertEqual(session.status().timerRemaining, 1)
        clock.now += 1
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testEndWhilePausedLeavesFlagAndNoLeftover() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: chargingOnly()), .ok)
        power.reading = onBattery
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(flag.writes, [true, false])

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(flag.writes, [true, false])
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(session.needsHelper)
        XCTAssertNil(session.retryLeftover())
        XCTAssertEqual(session.status().paused, false)
    }
}
