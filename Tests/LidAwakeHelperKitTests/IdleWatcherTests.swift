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

final class IdleWatcherTests: XCTestCase {
    private let source = FakeBusySource()
    private let clock = FakeClock()

    private func makeWatcher(minutes: Int = 5) -> IdleWatcher {
        let watcher = IdleWatcher(source: source, clock: clock)
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
        let watcher = IdleWatcher(source: source, clock: clock)
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
