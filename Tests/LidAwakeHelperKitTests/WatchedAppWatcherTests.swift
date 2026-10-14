import LidAwakeShared
import XCTest
@testable import LidAwakeHelperKit

private final class QuietSource: BusySignalSource {
    var ownPathPrefix: String? = "/Programs/Own.app/"
    var cpuBusySeconds: Double = 0
    var inputIdleSeconds: Double = 600
    var sleepRequests: [SleepRequest] = []

    func read() -> BusySample {
        BusySample(cpuBusySeconds: cpuBusySeconds, inputIdleSeconds: inputIdleSeconds, sleepRequests: sleepRequests)
    }
}

private final class StepClock: SessionClock {
    var now: TimeInterval = 1000
}

/// An editor and a console, each with one program it started; the programs' processor seconds grow
/// as the test says.
private final class AppProcesses: ProcessTimeSource {
    static let editor = "/Applications/Editor.app"
    static let console = "/Applications/Utilities/Console.app"

    var editorAgentSeconds = 0.0
    var consoleShellSeconds = 0.0
    var editorSelfSeconds = 0.0
    var isReadable = true

    func read() -> [ProcessTime]? {
        guard isReadable else { return nil }
        return [
            process(100, parent: 1, "\(Self.editor)/Contents/MacOS/Editor", editorSelfSeconds),
            process(200, parent: 100, "/usr/local/bin/agent", editorAgentSeconds),
            process(300, parent: 1, "\(Self.console)/Contents/MacOS/Console", 0),
            process(301, parent: 300, "/bin/zsh", consoleShellSeconds),
        ]
    }

    private func process(_ pid: Int32, parent: Int32, _ path: String, _ seconds: Double) -> ProcessTime {
        ProcessTime(
            pid: pid,
            startTime: 1,
            name: (path as NSString).lastPathComponent,
            cpuTime: UInt64(seconds * 1000),
            parentPID: parent,
            path: path,
            cpuSecondsWithReaped: seconds
        )
    }
}

final class WatchedAppWatcherTests: XCTestCase {
    private let source = QuietSource()
    private let clock = StepClock()
    private let processes = AppProcesses()

    private func makeWatcher(minutes: Int = 5, apps: [String] = [AppProcesses.editor]) -> IdleWatcher {
        let watcher = IdleWatcher(source: source, clock: clock, processes: processes)
        watcher.sample()
        watcher.watch(appPaths: apps)
        watcher.require(minutes: minutes)
        return watcher
    }

    /// One minute in which the editor's program spends `editor` seconds and the console's `console`.
    private func runMinute(
        _ watcher: IdleWatcher,
        editor: Double = 0,
        console: Double = 0,
        input: Bool = false,
        holder: String? = nil,
        cores: Double = 0
    ) {
        source.inputIdleSeconds = input ? 5 : 600
        source.sleepRequests = holder.map {
            [SleepRequest(kind: "PreventUserIdleSystemSleep", processName: $0, executablePath: "/usr/bin/\($0)")]
        } ?? []
        source.cpuBusySeconds += cores * IdleWatcher.minuteSeconds
        processes.editorAgentSeconds += editor
        processes.consoleShellSeconds += console
        clock.now += IdleWatcher.minuteSeconds
        watcher.sample()
    }

    private func causes(_ watcher: IdleWatcher) -> [IdleCause] {
        watcher.takeEvents().map(\.cause)
    }

    // MARK: The count

    func testABusyWatchedAppStartsTheCountOver() {
        let watcher = makeWatcher()
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        runMinute(watcher, editor: 0.67)
        XCTAssertEqual(watcher.countedMinutes, 0)
        runMinute(watcher, editor: 0.16)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testOneBusyMinuteIsEnoughUnlikeTheLoad() {
        let watcher = makeWatcher()
        runMinute(watcher)
        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 1, "a load minute alone is forgiven")
        runMinute(watcher, editor: 20)
        XCTAssertEqual(watcher.countedMinutes, 0)
    }

    func testTheAppItselfDoesNotCount() {
        let watcher = makeWatcher()
        processes.editorSelfSeconds += 5
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testAppsNotWatchedDoNotCount() {
        let watcher = makeWatcher(apps: [AppProcesses.editor])
        runMinute(watcher, console: 30)
        XCTAssertEqual(watcher.countedMinutes, 1)

        watcher.watch(appPaths: [])
        runMinute(watcher, editor: 30)
        XCTAssertEqual(watcher.countedMinutes, 2)
    }

    func testAnUnreadableProcessListCountsAsNoWork() {
        let watcher = makeWatcher()
        processes.isReadable = false
        runMinute(watcher, editor: 30)
        XCTAssertEqual(watcher.countedMinutes, 1)
        processes.isReadable = true
        // The minute before could not be read, so this one has nothing to measure from.
        runMinute(watcher, editor: 30)
        XCTAssertEqual(watcher.countedMinutes, 2)
        runMinute(watcher, editor: 30)
        XCTAssertEqual(watcher.countedMinutes, 0)
    }

    func testWithoutTheCountNothingIsWatched() {
        let watcher = makeWatcher(minutes: 0)
        runMinute(watcher, editor: 30)
        XCTAssertEqual(watcher.status().watched, [WatchedAppState(name: "Editor", isBusy: false)])
        XCTAssertEqual(watcher.takeEvents(), [])
    }

    // MARK: Events

    func testCausesComeInTheOrderOfTheRules() {
        let watcher = makeWatcher(minutes: 30)
        runMinute(watcher, editor: 1, holder: "worker")
        runMinute(watcher, editor: 1, input: true)
        runMinute(watcher, input: true)
        for _ in 0..<3 { runMinute(watcher, editor: 1, cores: 2) }
        for _ in 0..<3 { runMinute(watcher, cores: 2) }
        runMinute(watcher)
        XCTAssertEqual(causes(watcher), [
            .app("worker"),
            .watched("Editor"),
            .input,
            .watched("Editor"),
            .load(busiest: nil),
            .idle(minutes: 30),
        ])
    }

    func testAnEventOnlyWhenTheCauseChanges() {
        let watcher = makeWatcher(minutes: 30, apps: [AppProcesses.editor, AppProcesses.console])
        runMinute(watcher)
        runMinute(watcher, editor: 1)
        runMinute(watcher, editor: 1)
        runMinute(watcher, console: 1)
        runMinute(watcher, editor: 1, console: 1)
        runMinute(watcher)
        XCTAssertEqual(causes(watcher), [
            .idle(minutes: 30),
            .watched("Editor"),
            .watched("Console"),
            .idle(minutes: 30),
        ])
    }

    // MARK: Status

    func testStatusListsEveryWatchedApp() {
        let watcher = makeWatcher(apps: [AppProcesses.editor, AppProcesses.console])
        XCTAssertEqual(watcher.status().watchedToken, "\"Editor:idle,Console:idle\"")
        runMinute(watcher, editor: 2)
        XCTAssertEqual(watcher.status().watchedToken, "\"Editor:busy,Console:idle\"")
        runMinute(watcher, console: 2)
        XCTAssertEqual(watcher.status().watchedToken, "\"Editor:idle,Console:busy\"")

        watcher.restart()
        XCTAssertEqual(watcher.status().watchedToken, "\"Editor:idle,Console:idle\"")
        watcher.watch(appPaths: [])
        XCTAssertEqual(watcher.status().watchedToken, "none")
    }
}
