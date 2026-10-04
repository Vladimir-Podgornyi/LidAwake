import XCTest
@testable import LidAwakeHelperKit

private final class FakeRunner: CommandRunning {
    var results: [CommandResult]
    private(set) var calls: [(path: String, arguments: [String], timeout: TimeInterval)] = []

    init(_ results: [CommandResult]) {
        self.results = results
    }

    func run(_ path: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        calls.append((path, arguments, timeout))
        return results.removeFirst()
    }
}

private func pmsetOutput(sleepDisabled: String?) -> String {
    var lines = ["System-wide power settings:"]
    if let sleepDisabled {
        lines.append(" SleepDisabled\t\t\(sleepDisabled)")
    }
    lines += [
        "Currently in use:",
        " standby              1",
        " sleep                1 (sleep prevented by powerd, sharingd)",
        " hibernatemode        3",
        " displaysleep         10",
    ]
    return lines.joined(separator: "\n") + "\n"
}

final class PmsetOutputTests: XCTestCase {
    func testReadsOne() throws {
        XCTAssertTrue(try PmsetOutput.sleepDisabled(in: pmsetOutput(sleepDisabled: "1")))
    }

    func testReadsZero() throws {
        XCTAssertFalse(try PmsetOutput.sleepDisabled(in: pmsetOutput(sleepDisabled: "0")))
    }

    func testMissingLineMeansZero() throws {
        XCTAssertFalse(try PmsetOutput.sleepDisabled(in: pmsetOutput(sleepDisabled: nil)))
    }

    func testUnexpectedValueFails() {
        for value in ["2", "yes", "1 extra", ""] {
            XCTAssertThrowsError(try PmsetOutput.sleepDisabled(in: pmsetOutput(sleepDisabled: value)), value)
        }
    }

    func testUnrecognisedOutputFails() {
        XCTAssertThrowsError(try PmsetOutput.sleepDisabled(in: ""))
        XCTAssertThrowsError(try PmsetOutput.sleepDisabled(in: "Usage: pmset <options>\n"))
    }
}

final class PmsetSleepFlagTests: XCTestCase {
    func testReadRunsPmsetGet() throws {
        let runner = FakeRunner([CommandResult(status: 0, output: pmsetOutput(sleepDisabled: "1"))])
        XCTAssertTrue(try PmsetSleepFlag(runner: runner).read())
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/pmset"])
        XCTAssertEqual(runner.calls.map(\.arguments), [["-g"]])
    }

    func testReadFailsOnExitStatus() {
        let runner = FakeRunner([CommandResult(status: 1, output: "")])
        XCTAssertThrowsError(try PmsetSleepFlag(runner: runner).read()) { error in
            XCTAssertEqual(error as? SleepFlagError, .commandFailed(1))
        }
    }

    func testWriteSetsAndVerifies() throws {
        let runner = FakeRunner([
            CommandResult(status: 0, output: ""),
            CommandResult(status: 0, output: pmsetOutput(sleepDisabled: "1")),
        ])
        try PmsetSleepFlag(runner: runner).write(true)
        XCTAssertEqual(runner.calls.map(\.arguments), [["-a", "disablesleep", "1"], ["-g"]])
        XCTAssertEqual(runner.calls.map(\.path), ["/usr/bin/pmset", "/usr/bin/pmset"])
        XCTAssertEqual(runner.calls.first?.timeout, 10)
    }

    func testWriteClears() throws {
        let runner = FakeRunner([
            CommandResult(status: 0, output: ""),
            CommandResult(status: 0, output: pmsetOutput(sleepDisabled: "0")),
        ])
        try PmsetSleepFlag(runner: runner).write(false)
        XCTAssertEqual(runner.calls.first?.arguments, ["-a", "disablesleep", "0"])
    }

    func testWriteFailsWhenValueDidNotChange() {
        let runner = FakeRunner([
            CommandResult(status: 0, output: ""),
            CommandResult(status: 0, output: pmsetOutput(sleepDisabled: "0")),
        ])
        XCTAssertThrowsError(try PmsetSleepFlag(runner: runner).write(true)) { error in
            XCTAssertEqual(error as? SleepFlagError, .notApplied(expected: true))
        }
    }

    func testWriteFailsOnExitStatus() {
        let runner = FakeRunner([CommandResult(status: 1, output: "")])
        XCTAssertThrowsError(try PmsetSleepFlag(runner: runner).write(true)) { error in
            XCTAssertEqual(error as? SleepFlagError, .commandFailed(1))
        }
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testProcessRunnerTimesOut() {
        XCTAssertThrowsError(try ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.2)) { error in
            XCTAssertEqual(error as? SleepFlagError, .timedOut)
        }
    }
}
