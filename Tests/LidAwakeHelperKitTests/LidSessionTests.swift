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

final class LidSessionTests: XCTestCase {
    private var flag = FakeFlag(false)
    private var marker = FakeMarker()
    private let clock = FakeClock()

    private func makeSession() -> LidSession {
        LidSession(flag: flag, marker: marker, clock: clock)
    }

    func testOwnSessionSetsAndClearsFlag() {
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(marker.isSet)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertEqual(session.status(), SessionStatus(flag: .on, session: .ours, message: nil))

        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.status(), SessionStatus(flag: .off, session: .noSession, message: nil))
    }

    func testForeignFlagIsNeverTouched() {
        flag = FakeFlag(true)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120), .ok)
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

        let result = session.start(lease: 120)
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

        XCTAssertEqual(session.start(lease: 120).code, .flagWriteFailed)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
    }

    func testLeftoverMarkerWithFlagSetCountsAsOurs() {
        flag = FakeFlag(true)
        marker = FakeMarker(true)
        let session = makeSession()

        XCTAssertEqual(session.start(lease: 120), .ok)
        XCTAssertEqual(session.ownership, .ours)
        XCTAssertEqual(session.end(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testRenewMovesDeadline() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        clock.now += 100
        XCTAssertEqual(session.renew(lease: 120), .ok)
        clock.now += 100
        XCTAssertNil(session.expireIfNeeded())
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(flag.value)

        clock.now += 20
        XCTAssertEqual(session.expireIfNeeded(), .ok)
        XCTAssertFalse(session.isActive)
    }

    func testRenewWithoutSession() {
        let session = makeSession()
        XCTAssertEqual(session.renew(lease: 120).code, .noSession)
        XCTAssertEqual(flag.writes, [])
    }

    func testRenewRestoresClearedFlag() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120), .ok)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(flag.writes, [true, true])
    }

    func testRenewDoesNotRestoreForeignFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        flag.value = false
        XCTAssertEqual(session.renew(lease: 120), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertEqual(flag.writes, [])
    }

    func testRenewReportsRestoreFailure() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        flag.value = false
        flag.writeFails = true
        XCTAssertEqual(session.renew(lease: 120).code, .flagWriteFailed)
    }

    func testExpiredLeaseEndsOwnSession() {
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        clock.now += 119
        XCTAssertNil(session.expireIfNeeded())
        XCTAssertTrue(flag.value)

        clock.now += 1
        XCTAssertEqual(session.expireIfNeeded(), .ok)
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(marker.isSet)
    }

    func testExpiredLeaseKeepsForeignFlag() {
        flag = FakeFlag(true)
        let session = makeSession()
        XCTAssertEqual(session.start(lease: 120), .ok)

        clock.now += 120
        XCTAssertEqual(session.expireIfNeeded(), .ok)
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
        XCTAssertEqual(session.start(lease: 120), .ok)

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

        let first = LidSession(flag: flag, marker: FileOwnershipMarker(directory: directory), clock: clock)
        XCTAssertEqual(first.start(lease: 120), .ok)
        XCTAssertTrue(flag.value)

        let fileMarker = FileOwnershipMarker(directory: directory)
        XCTAssertTrue(fileMarker.isSet)
        let second = LidSession(flag: flag, marker: fileMarker, clock: clock)
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(second.clearLeftover(), .ok)
        XCTAssertFalse(flag.value)
        XCTAssertFalse(FileOwnershipMarker(directory: directory).isSet)
    }
}
