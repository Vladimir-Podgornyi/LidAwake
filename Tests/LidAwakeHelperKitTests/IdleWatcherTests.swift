import LidAwakeShared
import XCTest
@testable import LidAwakeHelperKit

private final class FakeBusySource: BusySignalSource {
    var ownPathPrefix: String? = "/Programs/Own.app/"
    /// Core-seconds spent busy; nil stands for a counter that cannot be read.
    var cpuBusySeconds: Double? = 0
    var inputIdleSeconds: Double? = 600
    var sleepRequests: [SleepRequest]? = []
    private(set) var readCount = 0

    func read() -> BusySample {
        readCount += 1
        return BusySample(
            cpuBusySeconds: cpuBusySeconds,
            inputIdleSeconds: inputIdleSeconds,
            sleepRequests: sleepRequests
        )
    }
}

private final class FakeClock: SessionClock {
    var now: TimeInterval = 1000
}

private final class FakeProcesses: ProcessTimeSource {
    /// Nil stands for a list that cannot be read.
    var list: [ProcessTime]? = []
    private(set) var readCount = 0

    func read() -> [ProcessTime]? {
        readCount += 1
        return list
    }
}

final class IdleWatcherTests: XCTestCase {
    private let source = FakeBusySource()
    private let clock = FakeClock()
    private let processes = FakeProcesses()

    private func makeWatcher(minutes: Int = 5) -> IdleWatcher {
        let watcher = IdleWatcher(source: source, clock: clock, processes: processes)
        // The reading the first minute is measured from, as the helper takes it when it starts.
        watcher.sample()
        watcher.require(minutes: minutes)
        return watcher
    }

    /// One minute of the Mac's working time with the given load, in busy cores.
    private func runMinute(_ watcher: IdleWatcher, cores: Double = 0) {
        clock.now += IdleWatcher.minuteSeconds
        if let busy = source.cpuBusySeconds {
            source.cpuBusySeconds = busy + cores * IdleWatcher.minuteSeconds
        }
        watcher.sample()
    }

    private func request(
        kind: String = "PreventUserIdleSystemSleep",
        name: String = "worker",
        path: String? = "/usr/bin/worker"
    ) -> SleepRequest {
        SleepRequest(kind: kind, processName: name, executablePath: path)
    }

    // MARK: The count

    func testQuietMinutesAddUpOneByOne() {
        let watcher = makeWatcher(minutes: 5)
        for minute in 1...5 {
            runMinute(watcher)
            XCTAssertEqual(watcher.countedMinutes, minute)
        }
        XCTAssertEqual(watcher.status().state, .counting)
        XCTAssertEqual(watcher.status().token, "counting:5/5")
    }

    func testHalfAMinuteDoesNotCount() {
        let watcher = makeWatcher(minutes: 5)
        clock.now += IdleWatcher.minuteSeconds / 2
        watcher.sample()
        XCTAssertEqual(watcher.countedMinutes, 0)
        clock.now += IdleWatcher.minuteSeconds / 2
        watcher.sample()
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testSleepRequestClearsTheCount() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        source.sleepRequests = [request()]
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)
    }

    func testRequestSeenPartWayThroughCountsForTheWholeMinute() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)

        clock.now += 10
        source.sleepRequests = [request()]
        watcher.sample()
        source.sleepRequests = []
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)
    }

    func testInputClearsTheCount() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        source.inputIdleSeconds = IdleWatcher.recentInputSeconds - 1
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)

        source.inputIdleSeconds = IdleWatcher.recentInputSeconds
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testTwoLoadMinutesLeaveTheCountAndTheThirdClearsIt() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 2)
        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 2)
        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 0)

        // Every further load minute in a row keeps it at zero.
        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 0)
    }

    func testAQuietMinuteBreaksTheRunOfLoadMinutes() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher, cores: 2)
        runMinute(watcher, cores: 2)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        runMinute(watcher, cores: 2)
        runMinute(watcher, cores: 2)
        XCTAssertEqual(watcher.countedMinutes, 2)
    }

    func testLoadAtTheThresholdIsNotWork() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher, cores: IdleWatcher.busyCores)
        XCTAssertEqual(watcher.countedMinutes, 1)

        runMinute(watcher, cores: IdleWatcher.busyCores + 0.1)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    // MARK: When the count does not run

    func testTheCountStaysAtZeroWhileTheSettingIsOff() {
        let watcher = makeWatcher(minutes: 0)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)
        XCTAssertEqual(watcher.status().state, .off)
        XCTAssertEqual(watcher.status().token, "off")
    }

    func testStoppingTheCountAndStartingItAgainBeginsFromZero() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        watcher.require(minutes: 0)
        XCTAssertEqual(watcher.countedMinutes, 0)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)

        watcher.require(minutes: 5)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testChangingTheNumberOfMinutesBeginsFromZero() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)

        watcher.require(minutes: 10)
        XCTAssertEqual(watcher.countedMinutes, 0)
        XCTAssertEqual(watcher.status().requiredMinutes, 10)

        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)
        // The same number keeps the count going.
        watcher.require(minutes: 10)
        XCTAssertEqual(watcher.countedMinutes, 1)
    }

    func testRestartClearsTheCountAndKeepsTheRequirement() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher)
        watcher.restart()
        XCTAssertEqual(watcher.countedMinutes, 0)
        XCTAssertEqual(watcher.status().requiredMinutes, 5)
    }

    func testTheCountNeverPassesTheRequirement() {
        let watcher = makeWatcher(minutes: 2)
        for _ in 0..<5 {
            runMinute(watcher)
        }
        XCTAssertEqual(watcher.countedMinutes, 2)
    }

    // MARK: Signals that cannot be read

    func testUnreadableSignalsCountAsAbsent() {
        let watcher = makeWatcher(minutes: 5)
        source.cpuBusySeconds = nil
        source.inputIdleSeconds = nil
        source.sleepRequests = nil

        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 1)

        let status = watcher.status()
        XCTAssertNil(status.cores)
        XCTAssertNil(status.inputIdleSeconds)
        XCTAssertNil(status.holders)
        XCTAssertEqual(status.state, .counting)
        XCTAssertEqual(status.coresToken, "unreadable")
        XCTAssertEqual(status.inputToken, "unreadable")
        XCTAssertEqual(status.holdersToken, "unreadable")
    }

    func testACounterThatStepsBackIsUnreadable() {
        let watcher = makeWatcher(minutes: 5)
        runMinute(watcher, cores: 1)
        source.cpuBusySeconds = 0
        clock.now += IdleWatcher.minuteSeconds
        watcher.sample()
        XCTAssertNil(watcher.status().cores)
    }

    // MARK: What the helper sees

    func testTheLoadNeedsASpanToAverageOver() {
        let watcher = IdleWatcher(source: source, clock: clock, processes: processes)
        XCTAssertNil(watcher.status().cores)

        clock.now += IdleWatcher.shortestLoadWindow * 2
        source.cpuBusySeconds = 1
        XCTAssertEqual(try XCTUnwrap(watcher.status().cores), 0.5, accuracy: 0.0001)
    }

    func testStatusNamesWhatKeepsTheMacBusy() {
        let watcher = makeWatcher(minutes: 5)
        source.sleepRequests = [request(name: "worker"), request(name: "worker"), request(name: "other")]
        source.inputIdleSeconds = 5
        clock.now += 10
        var status = watcher.status()
        XCTAssertEqual(status.state, .busyApp)
        XCTAssertEqual(status.holders, ["worker", "other"])
        XCTAssertEqual(status.holdersToken, "\"worker,other\"")
        XCTAssertEqual(status.inputToken, "5.0")

        source.sleepRequests = []
        clock.now += 10
        status = watcher.status()
        XCTAssertEqual(status.state, .busyInput)
        XCTAssertEqual(status.holdersToken, "none")

        source.inputIdleSeconds = 600
        source.cpuBusySeconds = 100
        clock.now += 10
        status = watcher.status()
        XCTAssertEqual(status.state, .busyCPU)
        XCTAssertEqual(status.token, "busy-cpu")
    }

    func testARequestIsNamedBeforeTheLoad() {
        let watcher = makeWatcher(minutes: 5)
        source.sleepRequests = [request()]
        source.cpuBusySeconds = 100
        clock.now += 10
        XCTAssertEqual(watcher.status().state, .busyApp)
    }

    func testTheLoadIsNamedBeforeInput() {
        let watcher = makeWatcher(minutes: 5)
        source.inputIdleSeconds = 5
        source.cpuBusySeconds = 100
        clock.now += 10
        XCTAssertEqual(watcher.status().state, .busyCPU)
    }

    func testAskingForTheStatusOftenLeavesTheCountAlone() {
        let asked = makeWatcher(minutes: 30)
        let left = IdleWatcher(source: source, clock: clock, processes: processes)
        left.sample()
        left.require(minutes: 30)
        for _ in 1...10 {
            for _ in 1...12 {
                clock.now += 5
                _ = asked.status()
            }
            left.sample()
        }
        XCTAssertEqual(asked.countedMinutes, 10)
        XCTAssertEqual(left.countedMinutes, 10)
        XCTAssertEqual(asked.status().token, "counting:10/30")
    }

    // MARK: Which requests count

    func testOnlyRequestsThatMeanWorkCount() {
        let own = "/Programs/Own.app/"
        let counted = [
            request(kind: "PreventUserIdleSystemSleep", path: "/usr/bin/worker"),
            request(kind: "PreventSystemSleep", path: "/Programs/Other.app/Contents/MacOS/Other"),
            request(kind: "NoIdleSleepAssertion", path: "/opt/tools/bin/worker"),
            request(path: "/Users/someone/bin/worker"),
        ]
        let ignored = [
            request(kind: "UserIsActive", path: "/usr/bin/worker"),
            request(kind: "PreventUserIdleDisplaySleep", path: "/usr/bin/worker"),
            request(kind: "PreventDisplaySleep", path: "/usr/bin/worker"),
            request(path: "/System/Library/CoreServices/service"),
            request(path: "/System/Applications/Bundled.app/Contents/MacOS/Bundled"),
            request(path: "/usr/libexec/service"),
            request(path: "/usr/sbin/service"),
            request(path: "/sbin/service"),
            request(path: own + "Contents/MacOS/Own"),
            request(path: own + "Contents/MacOS/OwnHelper"),
            request(path: nil),
        ]
        for item in counted {
            XCTAssertTrue(BusyRules.counts(item, ownPathPrefix: own), "\(item)")
        }
        for item in ignored {
            XCTAssertFalse(BusyRules.counts(item, ownPathPrefix: own), "\(item)")
        }
        XCTAssertEqual(BusyRules.holders(in: ignored, ownPathPrefix: own), [])
    }

    func testEveryHolderIsNamedOnce() {
        let requests = [
            request(name: "second", path: "/usr/bin/second"),
            request(name: "first", path: "/usr/bin/first"),
            request(name: "second", path: "/usr/bin/second"),
            request(name: "left out", path: "/usr/libexec/service"),
        ]
        XCTAssertEqual(BusyRules.holders(in: requests, ownPathPrefix: nil), ["second", "first"])
    }

    func testRequestsThatDoNotCountLeaveTheCountAlone() {
        let watcher = makeWatcher(minutes: 5)
        source.sleepRequests = [
            request(path: "/System/Library/CoreServices/service"),
            request(path: "/usr/libexec/service"),
            request(path: (source.ownPathPrefix ?? "") + "Contents/MacOS/OwnHelper"),
            request(kind: "PreventUserIdleDisplaySleep", path: "/usr/bin/worker"),
        ]
        runMinute(watcher)
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 2)
        XCTAssertEqual(watcher.status().holders, [])

        source.sleepRequests?.append(request(path: "/usr/bin/worker"))
        runMinute(watcher)
        XCTAssertEqual(watcher.countedMinutes, 0)
        XCTAssertEqual(watcher.status().holders, ["worker"])
    }

    func testWithoutAnOwnPathEveryRequestCounts() {
        XCTAssertTrue(BusyRules.counts(request(path: "/Programs/Own.app/Contents/MacOS/Own"), ownPathPrefix: nil))
    }
}

final class IdleEventTests: XCTestCase {
    private let source = FakeBusySource()
    private let clock = FakeClock()
    private let processes = FakeProcesses()
    private var wallTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeWatcher(minutes: Int = 5) -> IdleWatcher {
        let watcher = IdleWatcher(
            source: source,
            clock: clock,
            processes: processes,
            wallClock: { [unowned self] in wallTime }
        )
        watcher.sample()
        watcher.require(minutes: minutes)
        return watcher
    }

    private enum Minute {
        case quiet
        case app([String])
        case input
        case load
        case appAndInput
        case inputAndLoad
    }

    /// One minute of working time, read every 5 seconds as the helper does.
    private func run(_ watcher: IdleWatcher, _ minute: Minute) {
        let cores: Double
        switch minute {
        case .load, .inputAndLoad: cores = 2
        default: cores = 0
        }
        switch minute {
        case .input, .appAndInput, .inputAndLoad: source.inputIdleSeconds = 5
        default: source.inputIdleSeconds = 600
        }
        switch minute {
        case .app(let names): source.sleepRequests = names.map(request)
        case .appAndInput: source.sleepRequests = [request("worker")]
        default: source.sleepRequests = []
        }
        for _ in 0..<12 {
            clock.now += 5
            wallTime += 5
            source.cpuBusySeconds = (source.cpuBusySeconds ?? 0) + cores * 5
            watcher.sample()
        }
    }

    private func request(_ name: String) -> SleepRequest {
        SleepRequest(kind: "PreventUserIdleSystemSleep", processName: name, executablePath: "/usr/bin/\(name)")
    }

    private func process(_ pid: Int32, _ name: String, _ cpuTime: UInt64, started: UInt64 = 1) -> ProcessTime {
        ProcessTime(pid: pid, startTime: started, name: name, cpuTime: cpuTime)
    }

    private func causes(_ watcher: IdleWatcher) -> [IdleCause] {
        watcher.takeEvents().map(\.cause)
    }

    // MARK: Changes only

    func testEachStateGivesAnEventWhenItBegins() {
        let watcher = makeWatcher()
        run(watcher, .quiet)
        run(watcher, .app(["worker"]))
        run(watcher, .input)
        run(watcher, .load)
        run(watcher, .load)
        run(watcher, .load)
        run(watcher, .quiet)
        XCTAssertEqual(causes(watcher), [
            .idle(minutes: 5),
            .app("worker"),
            .input,
            .load(busiest: nil),
            .idle(minutes: 5),
        ])
    }

    func testTheSameCauseInARowIsOneEvent() {
        let watcher = makeWatcher(minutes: 30)
        for _ in 0..<3 { run(watcher, .app(["worker"])) }
        for _ in 0..<3 { run(watcher, .input) }
        for _ in 0..<6 { run(watcher, .load) }
        XCTAssertEqual(causes(watcher), [.app("worker"), .input, .load(busiest: nil)])
    }

    func testAnotherProgramNameIsANewEvent() {
        let watcher = makeWatcher()
        run(watcher, .app(["worker"]))
        run(watcher, .app(["worker"]))
        run(watcher, .app(["other"]))
        XCTAssertEqual(causes(watcher), [.app("worker"), .app("other")])
    }

    func testTheSmallestNameSeenInTheMinuteIsTaken() {
        let watcher = makeWatcher()
        source.sleepRequests = [request("second")]
        clock.now += 30
        watcher.sample()
        // The request ends part way through; the other program holds one to the end.
        run(watcher, .app(["third"]))
        let names = causes(watcher)
        XCTAssertEqual(names.last, .app("second"))
        run(watcher, .app(["third", "first"]))
        XCTAssertEqual(causes(watcher), [.app("first")])
    }

    // MARK: Load

    func testOneOrTwoLoadMinutesChangeNothing() {
        let watcher = makeWatcher(minutes: 10)
        run(watcher, .quiet)
        XCTAssertEqual(causes(watcher), [.idle(minutes: 10)])
        run(watcher, .load)
        run(watcher, .load)
        XCTAssertEqual(causes(watcher), [])
        // The state is still idle, so the next quiet minute is no news.
        run(watcher, .quiet)
        XCTAssertEqual(causes(watcher), [])

        run(watcher, .input)
        run(watcher, .load)
        run(watcher, .load)
        run(watcher, .input)
        XCTAssertEqual(causes(watcher), [.input])
    }

    func testTheThirdLoadMinuteNamesTheBusiestProcess() {
        processes.list = [process(10, "steady", 500), process(11, "spiky", 100)]
        let watcher = makeWatcher()
        processes.list = [process(10, "steady", 600), process(11, "spiky", 150)]
        run(watcher, .load)
        processes.list = [process(10, "steady", 700), process(11, "spiky", 200)]
        run(watcher, .load)
        // Over its whole life "steady" spent more; in this minute "spiky" did.
        processes.list = [process(10, "steady", 710), process(11, "spiky", 400)]
        run(watcher, .load)
        XCTAssertEqual(watcher.takeEvents().map(\.cause), [.load(busiest: "spiky")])
    }

    func testANewProcessCountsFromZero() {
        processes.list = [process(10, "old", 1000)]
        let watcher = makeWatcher()
        run(watcher, .load)
        run(watcher, .load)
        // The new process holds the old one's number but started later; both counts are its own.
        processes.list = [process(10, "old", 1100), process(12, "new", 80), process(10, "reused", 90, started: 9)]
        run(watcher, .load)
        XCTAssertEqual(causes(watcher), [.load(busiest: "old")])

        processes.list = [process(10, "old", 1100), process(12, "new", 80)]
        let second = makeWatcher()
        run(second, .load)
        run(second, .load)
        processes.list = [process(10, "old", 1200), process(12, "new", 90), process(13, "newer", 300)]
        run(second, .load)
        XCTAssertEqual(causes(second), [.load(busiest: "newer")])
    }

    func testAProcessThatEndedDoesNotCount() {
        processes.list = [process(10, "gone", 0), process(11, "stays", 0)]
        let watcher = makeWatcher()
        run(watcher, .load)
        run(watcher, .load)
        processes.list = [process(11, "stays", 50)]
        run(watcher, .load)
        XCTAssertEqual(causes(watcher), [.load(busiest: "stays")])
    }

    func testAListThatCannotBeReadGivesNoName() {
        processes.list = nil
        let watcher = makeWatcher()
        processes.list = [process(10, "worker", 500)]
        run(watcher, .load)
        run(watcher, .load)
        processes.list = nil
        run(watcher, .load)
        XCTAssertEqual(causes(watcher), [.load(busiest: nil)])

        // Unreadable at the start of the minute: the times cannot be compared either.
        processes.list = nil
        let second = makeWatcher()
        run(second, .load)
        run(second, .load)
        processes.list = nil
        run(second, .load)
        processes.list = [process(10, "worker", 900)]
        XCTAssertEqual(causes(second), [.load(busiest: nil)])
    }

    func testBusiestProcessComparesTheMinuteOnly() {
        let start = [process(1, "a", 100), process(2, "b", 10), process(3, "gone", 0)]
        let end = [process(1, "a", 120), process(2, "b", 60), process(4, "started", 40)]
        XCTAssertEqual(BusiestProcess.name(from: start, to: end), "b")
        XCTAssertNil(BusiestProcess.name(from: nil, to: end))
        XCTAssertNil(BusiestProcess.name(from: start, to: nil))
        XCTAssertNil(BusiestProcess.name(from: end, to: end), "nothing spent any time")
    }

    // MARK: Order of the rules

    func testARequestAndInputInOneMinuteAreTheProgram() {
        let watcher = makeWatcher()
        run(watcher, .appAndInput)
        XCTAssertEqual(causes(watcher), [.app("worker")])
    }

    func testInputAndLoadInOneMinuteAreInput() {
        let watcher = makeWatcher()
        for _ in 0..<4 { run(watcher, .inputAndLoad) }
        XCTAssertEqual(causes(watcher), [.input])
    }

    // MARK: Idle

    func testOnlyTheFirstQuietMinuteIsAnEvent() {
        let watcher = makeWatcher(minutes: 20)
        run(watcher, .input)
        _ = watcher.takeEvents()
        for _ in 0..<5 { run(watcher, .quiet) }
        XCTAssertEqual(causes(watcher), [.idle(minutes: 20)])
        XCTAssertEqual(watcher.countedMinutes, 5)
    }

    // MARK: Restart and when the count does not run

    func testAfterARestartTheFirstMinuteIsAnEventAgain() {
        let watcher = makeWatcher()
        run(watcher, .quiet)
        watcher.restart()
        run(watcher, .quiet)
        watcher.require(minutes: 10)
        run(watcher, .quiet)
        // A pause stops the count; resuming starts it again.
        watcher.require(minutes: 0)
        watcher.require(minutes: 10)
        run(watcher, .quiet)
        XCTAssertEqual(causes(watcher), [.idle(minutes: 5), .idle(minutes: 5), .idle(minutes: 10), .idle(minutes: 10)])
    }

    func testNoEventsAndNoProcessListWithoutTheCount() {
        let watcher = IdleWatcher(source: source, clock: clock, processes: processes, wallClock: { [unowned self] in wallTime })
        watcher.sample()
        // No session, a paused session and the setting off all leave the requirement at zero.
        watcher.require(minutes: 0)
        watcher.restart()
        for minute in [Minute.quiet, .app(["worker"]), .input, .load, .load, .load, .quiet] {
            run(watcher, minute)
        }
        XCTAssertEqual(watcher.takeEvents(), [])
        XCTAssertEqual(processes.readCount, 0)
    }

    func testTheProcessListIsReadOnceAMinute() {
        let watcher = makeWatcher()
        XCTAssertEqual(processes.readCount, 1, "at the start of the count")
        for _ in 0..<3 { run(watcher, .quiet) }
        XCTAssertEqual(processes.readCount, 4)
        _ = watcher.status()
        XCTAssertEqual(processes.readCount, 4)
        watcher.require(minutes: 0)
        run(watcher, .quiet)
        XCTAssertEqual(processes.readCount, 4)
    }

    // MARK: Time and storage

    func testTheEventTimeIsTheEndOfTheMinuteByTheWallClock() {
        let watcher = makeWatcher()
        run(watcher, .quiet)
        let first = wallTime
        // The Mac slept for an hour: the working clock stood still, the wall clock did not.
        wallTime += 3600
        run(watcher, .input)
        XCTAssertEqual(watcher.takeEvents().map(\.time), [first, wallTime])
    }

    func testAtMostTwoHundredEventsAreKept() {
        let watcher = makeWatcher()
        for minute in 0..<(IdleWatcher.eventCapacity + 10) {
            run(watcher, minute.isMultiple(of: 2) ? .input : .quiet)
        }
        let events = watcher.takeEvents()
        XCTAssertEqual(events.count, 200)
        XCTAssertEqual(events.first?.cause, .input, "the ten oldest made room")
        XCTAssertEqual(events.last?.cause, .idle(minutes: 5))
    }

    func testTakenEventsAreNotHandedOverAgain() {
        let watcher = makeWatcher()
        run(watcher, .quiet)
        XCTAssertEqual(causes(watcher), [.idle(minutes: 5)])
        XCTAssertEqual(watcher.takeEvents(), [])
        run(watcher, .input)
        XCTAssertEqual(causes(watcher), [.input])
    }

    func testEventsLeaveTheCountAsItWas() {
        let watcher = makeWatcher(minutes: 5)
        let counts: [(Minute, Int)] = [
            (.quiet, 1), (.quiet, 2), (.load, 2), (.load, 2), (.load, 0), (.quiet, 1),
            (.app(["worker"]), 0), (.quiet, 1), (.input, 0), (.quiet, 1), (.quiet, 2),
        ]
        for (minute, expected) in counts {
            run(watcher, minute)
            XCTAssertEqual(watcher.countedMinutes, expected)
        }
    }
}
