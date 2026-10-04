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

    init(_ isSet: Bool = false) {
        self.isSet = isSet
    }

    func set() throws { isSet = true }
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
    private let power = FakePower()
    private let stopReasons = FakeStopReasons()
    private let wallTime = Date(timeIntervalSince1970: 1_800_000_000)
    private let noLimits = SafetySettings.off

    private func makeSession() -> LidSession {
        LidSession(
            flag: flag,
            marker: marker,
            clock: clock,
            power: power,
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

        clock.now += 100
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        clock.now += 100
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(flag.value)

        clock.now += 20
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

    func testRenewDoesNotRestoreForeignFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)
        XCTAssertFalse(flag.value)
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

        clock.now += 119
        XCTAssertNil(session.enforceLimits())
        XCTAssertTrue(flag.value)

        clock.now += 1
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testExpiredLeaseKeepsForeignFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        clock.now += 120
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
            power: power,
            stopReasons: stopReasons
        )
        XCTAssertEqual(first.start(lease: 120, safety: noLimits), .ok)
        XCTAssertTrue(flag.value)

        let fileMarker = FileOwnershipMarker(directory: directory)
        XCTAssertTrue(fileMarker.isSet)
        let second = LidSession(flag: flag, marker: fileMarker, clock: clock, power: power, stopReasons: stopReasons)
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(second.clearLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(FileOwnershipMarker(directory: directory).isSet)
    }

    // MARK: Safety limits

    private func limits(timer: Int = 0, battery: Int = 0) -> SafetySettings {
        SafetySettings(timerSeconds: timer, batteryLimitPercent: battery)
    }

    func testTimerEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 3600)), .ok)

        for _ in 0..<35 {
            clock.now += 100
            XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 3600)), .ok)
            XCTAssertNil(session.enforceLimits())
        }
        XCTAssertEqual(session.status().timerRemaining, 100)

        clock.now += 100
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertEqual(stopReasons.record, StopRecord(reason: .timer, time: wallTime))
    }

    func testTimerChangeCountsFromSessionStart() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 7200)), .ok)

        clock.now += 100
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 3600)), .ok)
        XCTAssertEqual(session.status().timerRemaining, 3500)

        clock.now += 100
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 300)), .ok)
        XCTAssertEqual(session.status().timerRemaining, 100)

        clock.now += 99
        XCTAssertNil(session.enforceLimits())
        clock.now += 1
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testShorterTimerPastElapsedTimeEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 7200)), .ok)

        clock.now += 200
        XCTAssertEqual(session.renew(lease: 120, safety: limits(timer: 180)), .ok)
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testTimerOffNeverEndsSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: limits(timer: 3600)), .ok)
        XCTAssertEqual(session.renew(lease: 120, safety: noLimits), .ok)

        clock.now += 100
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
        clock.now += 60
        XCTAssertEqual(session.enforceLimits(), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [])
        XCTAssertEqual(stopReasons.record?.reason, .timer)
    }

    func testExpiredLeaseRecordsReason() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120, safety: noLimits), .ok)

        clock.now += 120
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
                power: self.power,
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
        clock.now += 0.5
        XCTAssertEqual(session.status().timerRemaining, 3600)
        clock.now += 99.5
        XCTAssertEqual(session.status().timerRemaining, 3500)
    }
}
