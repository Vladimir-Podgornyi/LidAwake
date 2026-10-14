import XCTest
@testable import LidAwakeShared

final class WatchedAppsTests: XCTestCase {
    private let editor = "/Applications/Editor.app"
    private let threshold = 0.5

    private func process(
        _ pid: Int32,
        parent: Int32,
        _ path: String?,
        seconds: Double,
        startTime: UInt64? = nil
    ) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, startTime: startTime ?? UInt64(pid) * 10, parentPID: parent, path: path, cpuSeconds: seconds)
    }

    /// The editor itself: a main process and a helper inside the folder.
    private func editorProcesses(seconds: Double) -> [ProcessSnapshot] {
        [
            process(100, parent: 1, "\(editor)/Contents/MacOS/Editor", seconds: seconds),
            process(101, parent: 100, "\(editor)/Contents/Frameworks/Editor Helper.app/Contents/MacOS/Editor Helper", seconds: seconds),
        ]
    }

    private func reading(from start: [ProcessSnapshot], to end: [ProcessSnapshot]) -> WatchedAppReading {
        WatchedApps.readings(appPaths: [editor], from: start, to: end, busyAboveSeconds: threshold)[0]
    }

    // MARK: Groups

    func testProcessesInsideTheFolderDoNotCount() {
        let start = editorProcesses(seconds: 10)
        let end = editorProcesses(seconds: 15)
        XCTAssertEqual(WatchedApps.groups(appPath: editor, in: end), [])
        XCTAssertEqual(reading(from: start, to: end), WatchedAppReading(path: editor, busiestGroupSeconds: 0, isBusy: false))
    }

    func testOutsideProcessWithItsDescendantsIsOneGroup() {
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/Users/someone/.tools/agent/bin/agent", seconds: 0.2),
            process(201, parent: 200, "/bin/zsh", seconds: 0.2),
            process(202, parent: 201, "/usr/bin/make", seconds: 0.2),
        ]
        let groups = WatchedApps.groups(appPath: editor, in: end)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.pid)), [200, 201, 202])
        XCTAssertEqual(WatchedApps.groupSeconds(appPath: editor, from: [], to: end)[0], 0.6, accuracy: 1e-9)
        XCTAssertTrue(reading(from: [], to: end).isBusy)
    }

    func testDescendantRunningFromInsideTheFolderStaysInItsGroup() {
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/bin/zsh", seconds: 0),
            process(201, parent: 200, "\(editor)/Contents/Resources/app/bin/editor-cli", seconds: 0.3),
            process(202, parent: 201, "/usr/local/bin/tool", seconds: 0.3),
        ]
        let groups = WatchedApps.groups(appPath: editor, in: end)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.pid)), [200, 201, 202])
        XCTAssertEqual(reading(from: [], to: end).busiestGroupSeconds, 0.6, accuracy: 1e-9)
    }

    func testProcessWithoutAReadablePathStartsNoGroup() {
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, nil, seconds: 5),
            process(201, parent: 200, "/bin/zsh", seconds: 0.3),
        ]
        let groups = WatchedApps.groups(appPath: editor, in: end)
        XCTAssertEqual(groups.map { $0.map(\.pid) }, [[201]])
    }

    func testAnotherAppWithASimilarNameIsOutside() {
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/Applications/Editor.app Beta/tool", seconds: 1),
        ]
        XCTAssertEqual(WatchedApps.groups(appPath: editor, in: end).map { $0.map(\.pid) }, [[200]])
    }

    // MARK: Busy or not

    func testSixQuietGroupsLeaveTheAppIdleThoughTheirSumIsAbove() {
        let start = editorProcesses(seconds: 0) + (0..<6).map {
            process(200 + Int32($0), parent: 101, "/usr/local/bin/agent", seconds: 1)
        }
        let end = editorProcesses(seconds: 3) + (0..<6).map {
            process(200 + Int32($0), parent: 101, "/usr/local/bin/agent", seconds: 1.16)
        }
        let result = reading(from: start, to: end)
        XCTAssertEqual(result.busiestGroupSeconds, 0.16, accuracy: 1e-9)
        XCTAssertFalse(result.isBusy)
        XCTAssertEqual(WatchedApps.groupSeconds(appPath: editor, from: start, to: end).reduce(0, +), 0.96, accuracy: 1e-9)
    }

    func testOneThinkingGroupMakesTheAppBusy() {
        let start = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 1),
            process(201, parent: 101, "/usr/local/bin/agent", seconds: 1),
        ]
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 1.16),
            process(201, parent: 101, "/usr/local/bin/agent", seconds: 1.67),
        ]
        let result = reading(from: start, to: end)
        XCTAssertEqual(result.busiestGroupSeconds, 0.67, accuracy: 1e-9)
        XCTAssertTrue(result.isBusy)
    }

    func testCommandWhoseChildrenHaveEndedMakesTheAppBusy() {
        // The agent's own time barely moved; its finished commands are reaped into it.
        let start = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 5),
            process(201, parent: 200, "/bin/zsh", seconds: 2),
        ]
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 25.2),
        ]
        let result = reading(from: start, to: end)
        XCTAssertEqual(result.busiestGroupSeconds, 20.2, accuracy: 1e-9)
        XCTAssertTrue(result.isBusy)
    }

    func testEndedProcessDoesNotSubtract() {
        let start = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 1),
            process(201, parent: 200, "/usr/bin/long-job", seconds: 300),
        ]
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 1.3),
        ]
        XCTAssertEqual(reading(from: start, to: end).busiestGroupSeconds, 0.3, accuracy: 1e-9)
    }

    func testReusedProcessNumberCountsFromZero() {
        let start = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 100, startTime: 1),
        ]
        let end = editorProcesses(seconds: 0) + [
            process(200, parent: 101, "/usr/local/bin/agent", seconds: 0.4, startTime: 2),
        ]
        XCTAssertEqual(reading(from: start, to: end).busiestGroupSeconds, 0.4, accuracy: 1e-9)
    }

    func testAppThatIsNotRunningIsIdle() {
        let others = [
            process(300, parent: 1, "/Applications/Other.app/Contents/MacOS/Other", seconds: 0),
            process(301, parent: 300, "/bin/zsh", seconds: 40),
        ]
        XCTAssertEqual(reading(from: [], to: others), WatchedAppReading(path: editor, busiestGroupSeconds: 0, isBusy: false))
    }

    func testReadingsFollowTheGivenOrder() {
        let terminal = "/Applications/Utilities/Console.app"
        let end = editorProcesses(seconds: 0) + [
            process(300, parent: 1, "\(terminal)/Contents/MacOS/Console", seconds: 0),
            process(301, parent: 300, "/bin/zsh", seconds: 2),
        ]
        let readings = WatchedApps.readings(appPaths: [terminal, editor], from: [], to: end, busyAboveSeconds: threshold)
        XCTAssertEqual(readings.map(\.path), [terminal, editor])
        XCTAssertEqual(readings.map(\.isBusy), [true, false])
    }

    // MARK: Paths

    func testNames() {
        XCTAssertEqual(WatchedApps.name(ofAppAt: "/Applications/Editor.app"), "Editor")
        XCTAssertEqual(WatchedApps.name(ofAppAt: "/Applications/Utilities/Some Console.app"), "Some Console")
    }

    func testValidPaths() {
        XCTAssertTrue(WatchedApps.isValid([]))
        XCTAssertTrue(WatchedApps.isValid(["/Applications/Editor.app", "/Users/someone/Applications/Tool.app"]))
        XCTAssertFalse(WatchedApps.isValid(["Editor.app"]))
        XCTAssertFalse(WatchedApps.isValid(["/Applications/Editor"]))
        XCTAssertFalse(WatchedApps.isValid(["/Applications/.app"]))
        XCTAssertTrue(WatchedApps.isValid((1...20).map { "/Applications/App\($0).app" }))
        XCTAssertFalse(WatchedApps.isValid((1...21).map { "/Applications/App\($0).app" }))
    }
}
