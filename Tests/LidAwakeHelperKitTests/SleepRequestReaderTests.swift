import IOKit
import XCTest
@testable import LidAwakeHelperKit

private final class FakeClock: SessionClock {
    var now: TimeInterval = 1000
}

private final class FakeLog: SleepRequestLog {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }
}

final class SleepRequestReaderTests: XCTestCase {
    private let clock = FakeClock()
    private let log = FakeLog()
    /// Results the attempts return, in order; once used up, every attempt fails.
    private var attempts: [Result<[SleepRequest], SleepRequestFailure>] = []
    private var attemptCount = 0

    private let held = [SleepRequest(kind: "PreventUserIdleSystemSleep", processName: "Tool", executablePath: "/bin/tool")]
    private let notSuccess = SleepRequestFailure(code: kIOReturnInternalError, reason: .notSuccess)

    private func makeReader() -> SleepRequestReader {
        SleepRequestReader(
            attempt: { [unowned self] in
                attemptCount += 1
                return attempts.isEmpty ? .failure(notSuccess) : attempts.removeFirst()
            },
            clock: clock,
            log: log
        )
    }

    func testSuccessReturnsTheRequestsAtOnce() {
        let reader = makeReader()
        attempts = [.success(held)]

        XCTAssertEqual(reader.read(), held)
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(log.lines, [])
    }

    func testFailureFollowedBySuccessfulRepeatReturnsTheRequests() {
        let reader = makeReader()
        attempts = [.failure(notSuccess), .success(held)]

        XCTAssertEqual(reader.read(), held)
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(log.lines, ["Sleep requests unreadable: code 0xe00002c9, result is not success"])
    }

    func testTwoFailuresTakeAReadingFrom30SecondsAgo() {
        let reader = makeReader()
        attempts = [.success(held)]
        _ = reader.read()

        clock.now += 30
        attempts = [.failure(notSuccess), .failure(notSuccess)]

        XCTAssertEqual(reader.read(), held)
        XCTAssertEqual(attemptCount, 3)
    }

    func testTwoFailuresDoNotTakeAReadingFrom90SecondsAgo() {
        let reader = makeReader()
        attempts = [.success(held)]
        _ = reader.read()

        clock.now += 90
        attempts = [.failure(notSuccess), .failure(notSuccess)]

        XCTAssertNil(reader.read())
    }

    func testTwoFailuresWithoutAnyEarlierReadingAreUnreadable() {
        XCTAssertNil(makeReader().read())
    }

    func testTheSameFailureIsLoggedAtMostEvery30Seconds() {
        let reader = makeReader()

        _ = reader.read()
        clock.now += 29
        _ = reader.read()
        XCTAssertEqual(log.lines.count, 1)

        clock.now += 1
        _ = reader.read()
        XCTAssertEqual(log.lines.count, 2)
    }

    func testDifferentFailuresAreLoggedSeparately() {
        let reader = makeReader()
        attempts = [
            .failure(notSuccess),
            .failure(SleepRequestFailure(code: kIOReturnSuccess, reason: .emptyPointer)),
        ]

        _ = reader.read()

        XCTAssertEqual(log.lines, [
            "Sleep requests unreadable: code 0xe00002c9, result is not success",
            "Sleep requests unreadable: code 0x0, empty pointer",
        ])
    }
}
