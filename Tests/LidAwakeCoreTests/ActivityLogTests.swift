import Combine
import LidAwakeShared
import XCTest
@testable import LidAwakeCore

@MainActor
final class ActivityLogTests: XCTestCase {
    private var folder: URL!
    private var fileURL: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ActivityLogTests-\(UUID().uuidString)")
        fileURL = folder.appendingPathComponent("support/activity-log.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeLog(_ url: URL? = nil) -> ActivityLog {
        ActivityLog(fileURL: url ?? fileURL, now: { [unowned self] in clock })
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    private func writeFile(_ text: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL)
    }

    func testRecordAddsEntryAtCurrentTime() {
        let log = makeLog()
        log.record(.modeOn(.lidClosed))
        clock = at(60)
        log.record(.sleep)

        let expected = [
            ActivityEntry(time: at(0), event: .modeOn(.lidClosed)),
            ActivityEntry(time: at(60), event: .sleep),
        ]
        XCTAssertEqual(log.entries, expected)
        XCTAssertEqual(ActivityLog.read(from: fileURL), expected)
    }

    func testNewestTwoHundredAreKept() {
        let log = makeLog()
        for second in 0...ActivityLog.capacity {
            log.record(.wake, at: at(TimeInterval(second)))
        }

        XCTAssertEqual(log.entries.count, 200)
        XCTAssertEqual(log.entries.first?.time, at(1))
        XCTAssertEqual(log.entries.last?.time, at(200))
        XCTAssertEqual(ActivityLog.read(from: fileURL).count, 200)
    }

    func testEarlierEntryBeyondCapacityIsDropped() {
        let log = makeLog()
        for second in 1...ActivityLog.capacity {
            log.record(.wake, at: at(TimeInterval(second)))
        }
        log.record(.sleep, at: at(0))

        XCTAssertEqual(log.entries.count, 200)
        XCTAssertFalse(log.entries.contains { $0.event == .sleep })
    }

    func testEarlierEventGoesInPlace() {
        let log = makeLog()
        log.record(.modeOn(.lidClosed), at: at(0))
        log.record(.sleep, at: at(100))
        log.record(.modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20)), at: at(95))
        log.record(.wake, at: at(100))

        XCTAssertEqual(log.entries.map(\.event), [
            .modeOn(.lidClosed),
            .modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20)),
            .sleep,
            .wake,
        ])
        XCTAssertEqual(ActivityLog.read(from: fileURL), log.entries)
    }

    func testSameEntryIsRecordedOnce() {
        let log = makeLog()
        let event = ActivityEvent.modeOff(.lidClosed, .stopped(.battery, batteryPercent: 15))
        log.record(event, at: at(10))
        log.record(event, at: at(10))

        XCTAssertEqual(log.entries, [ActivityEntry(time: at(10), event: event)])
    }

    func testEntriesSurviveNewInstance() {
        let events: [ActivityEvent] = [
            .modeOn(.keepScreenOn),
            .modeOff(.keepScreenOn, .user),
            .modeOn(.lidClosed),
            .paused,
            .resumed,
            .modeOff(.lidClosed, .stopped(.timer, timerSeconds: 14400)),
            .modeOff(.lidClosed, .stopped(.battery, batteryPercent: 15)),
            .modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20)),
            .modeOff(.lidClosed, .stopped(.leaseExpired)),
            .modeOff(.lidClosed, .error("The \"helper\" did not answer.")),
            .modeOff(.lidClosed, .previousSession),
            .sleep,
            .wake,
        ]
        let log = makeLog()
        for (index, event) in events.enumerated() {
            log.record(event, at: at(TimeInterval(index) + 0.25))
        }

        XCTAssertEqual(makeLog().entries, log.entries)
        XCTAssertEqual(makeLog().entries.map(\.event), events)
    }

    func testMissingFileIsEmptyAndNotCreatedByReading() {
        let log = makeLog()
        XCTAssertEqual(log.entries, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
    }

    func testDamagedFileReadsEmptyAndNextRecordReplacesIt() throws {
        try writeFile("{\"version\": 1, \"entries\": [")
        let log = makeLog()
        XCTAssertEqual(log.entries, [])

        log.record(.sleep)
        XCTAssertEqual(ActivityLog.read(from: fileURL), [ActivityEntry(time: at(0), event: .sleep)])
    }

    func testOtherFormatReadsEmpty() throws {
        try writeFile("{\"version\": 2, \"entries\": [{\"kind\": \"sleep\", \"time\": 1800000000}]}")
        XCTAssertEqual(makeLog().entries, [])

        try writeFile("[1, 2, 3]")
        XCTAssertEqual(makeLog().entries, [])
    }

    func testUnknownAndDamagedEntriesAreSkipped() throws {
        try writeFile("""
        {"version": 1, "entries": [
          {"kind": "sleep", "time": 1800000000},
          {"kind": "kept-awake", "time": 1800000010, "cause": "load", "busiest": "process"},
          {"kind": "mode-off", "time": 1800000020, "mode": "lid-closed", "reason": "something-new"},
          {"kind": "mode-on", "time": 1800000030, "mode": "lid-closed"},
          {"kind": "wake"},
          42,
          {"kind": "wake", "time": 1800000040}
        ]}
        """)

        XCTAssertEqual(makeLog().entries, [
            ActivityEntry(time: at(0), event: .sleep),
            ActivityEntry(time: at(30), event: .modeOn(.lidClosed)),
            ActivityEntry(time: at(40), event: .wake),
        ])
    }

    func testIdleEventsAreStoredAndReadBack() throws {
        let log = makeLog()
        let events: [ActivityEvent] = [
            .keptAwakeByApp("Example"),
            .keptAwakeByLoad(busiest: "example-tool"),
            .keptAwakeByLoad(busiest: nil),
            .keptAwakeByInput,
            .idleStarted(minutes: 20),
        ]
        for (index, event) in events.enumerated() {
            log.record(event, at: at(TimeInterval(index * 60)))
        }
        XCTAssertEqual(ActivityLog.read(from: fileURL).map(\.event), events)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 1)
        let entries = try XCTUnwrap(object?["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["kind"] as? String }, ["busy-app", "busy-cpu", "busy-cpu", "busy-input", "idle-start"])
        XCTAssertEqual(entries[0]["name"] as? String, "Example")
        XCTAssertEqual(entries[1]["busiest"] as? String, "example-tool")
        XCTAssertNil(entries[2]["busiest"])
        XCTAssertEqual(entries[4]["minutes"] as? Int, 20)
    }

    func testIdleEntriesNextToAFutureKindAreRead() throws {
        try writeFile("""
        {"version": 1, "entries": [
          {"kind": "busy-app", "time": 1800000000, "name": "Example"},
          {"kind": "something-later", "time": 1800000010, "detail": "x"},
          {"kind": "busy-cpu", "time": 1800000020},
          {"kind": "busy-app", "time": 1800000025},
          {"kind": "idle-start", "time": 1800000030, "minutes": 10}
        ]}
        """)

        XCTAssertEqual(makeLog().entries, [
            ActivityEntry(time: at(0), event: .keptAwakeByApp("Example")),
            ActivityEntry(time: at(20), event: .keptAwakeByLoad(busiest: nil)),
            ActivityEntry(time: at(30), event: .idleStarted(minutes: 10)),
        ])
    }

    func testClearEmptiesLog() {
        let log = makeLog()
        log.record(.sleep)
        log.record(.wake)

        log.clear()
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(makeLog().entries, [])

        log.record(.sleep)
        XCTAssertEqual(makeLog().entries.count, 1)
    }

    func testObserverSeesAddedEntries() {
        let log = makeLog()
        var seen: [[ActivityEvent]] = []
        let subscription = log.objectWillChange.sink { [unowned log] in
            // Sent before the change, so the new list is read on the next turn, as a view does.
            DispatchQueue.main.async { seen.append(log.entries.map(\.event)) }
        }
        log.record(.sleep)
        log.record(.wake)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(seen, [[.sleep, .wake], [.sleep, .wake]])
        subscription.cancel()
    }

    func testObserverSeesClear() {
        let log = makeLog()
        log.record(.sleep)
        var changes = 0
        let subscription = log.objectWillChange.sink { changes += 1 }
        log.clear()

        XCTAssertEqual(changes, 1)
        XCTAssertEqual(log.entries, [])
        subscription.cancel()
    }

    func testRepeatedEntryDoesNotNotify() {
        let log = makeLog()
        log.record(.sleep, at: at(0))
        var changes = 0
        let subscription = log.objectWillChange.sink { changes += 1 }
        log.record(.sleep, at: at(0))

        XCTAssertEqual(changes, 0)
        subscription.cancel()
    }

    func testFileIsPrivate() throws {
        makeLog().record(.sleep)

        let manager = FileManager.default
        let file = try manager.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let folder = try manager.attributesOfItem(atPath: fileURL.deletingLastPathComponent().path)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let leftovers = try manager.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["activity-log.json"])
    }

    func testWriteFailureIsNotThrown() throws {
        // A file where the folder should be makes every write fail.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        let log = makeLog(blocker.appendingPathComponent("activity-log.json"))

        log.record(.sleep)
        log.record(.wake)
        XCTAssertEqual(log.entries.map(\.event), [.sleep, .wake])
        log.clear()
        XCTAssertEqual(log.entries, [])
    }

    func testFileFormat() throws {
        let log = makeLog()
        log.record(.modeOff(.lidClosed, .stopped(.timer, timerSeconds: 14400)), at: at(0.5))

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 1)
        let entry = (object?["entries"] as? [[String: Any]])?.first
        XCTAssertEqual(entry?["kind"] as? String, "mode-off")
        XCTAssertEqual(entry?["time"] as? Double, 1_800_000_000.5)
        XCTAssertEqual(entry?["mode"] as? String, "lid-closed")
        XCTAssertEqual(entry?["reason"] as? String, "timer")
        XCTAssertEqual(entry?["timer"] as? Int, 14400)
    }

    func testPrintedLines() {
        let zone = TimeZone(secondsFromGMT: 7200)!
        let time = ISO8601DateFormatter().date(from: "2026-10-11T22:10:03Z")!
        func line(_ event: ActivityEvent) -> String {
            ActivityToken.line(for: ActivityEntry(time: time, event: event), timeZone: zone)
        }

        let stamp = "2026-10-12T00:10:03+02:00"
        XCTAssertEqual(line(.modeOn(.lidClosed)), "\(stamp) mode-on mode=lid-closed")
        XCTAssertEqual(line(.modeOn(.keepScreenOn)), "\(stamp) mode-on mode=keep-screen-on")
        XCTAssertEqual(line(.modeOff(.keepScreenOn, .user)), "\(stamp) mode-off mode=keep-screen-on reason=user")
        XCTAssertEqual(
            line(.modeOff(.lidClosed, .stopped(.timer, timerSeconds: 14400))),
            "\(stamp) mode-off mode=lid-closed reason=timer timer=14400"
        )
        XCTAssertEqual(
            line(.modeOff(.lidClosed, .stopped(.battery, batteryPercent: 15))),
            "\(stamp) mode-off mode=lid-closed reason=battery battery=15"
        )
        XCTAssertEqual(
            line(.modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20))),
            "\(stamp) mode-off mode=lid-closed reason=idle idle=20"
        )
        XCTAssertEqual(
            line(.modeOff(.lidClosed, .error("Say \"hi\""))),
            "\(stamp) mode-off mode=lid-closed reason=error message=\"Say \\\"hi\\\"\""
        )
        XCTAssertEqual(line(.modeOff(.lidClosed, .previousSession)), "\(stamp) mode-off mode=lid-closed reason=previous-session")
        XCTAssertEqual(line(.paused), "\(stamp) paused")
        XCTAssertEqual(line(.resumed), "\(stamp) resumed")
        XCTAssertEqual(line(.sleep), "\(stamp) sleep")
        XCTAssertEqual(line(.wake), "\(stamp) wake")
        XCTAssertEqual(line(.keptAwakeByApp("Example")), "\(stamp) busy-app name=\"Example\"")
        XCTAssertEqual(line(.keptAwakeByLoad(busiest: "example-tool")), "\(stamp) busy-cpu busiest=\"example-tool\"")
        XCTAssertEqual(line(.keptAwakeByLoad(busiest: nil)), "\(stamp) busy-cpu")
        XCTAssertEqual(line(.keptAwakeByInput), "\(stamp) busy-input")
        XCTAssertEqual(line(.idleStarted(minutes: 20)), "\(stamp) idle-start minutes=20")

        let reasons: [(StopReason, String)] = [
            (.timer, "timer"), (.battery, "battery"), (.batteryUnreadable, "battery-unreadable"),
            (.thermal, "thermal"), (.thermalUnreadable, "thermal-unreadable"),
            (.powerUnreadable, "power-unreadable"), (.leaseExpired, "lease-expired"), (.idle, "idle"),
        ]
        for (reason, word) in reasons {
            XCTAssertEqual(line(.modeOff(.lidClosed, .stopped(reason))), "\(stamp) mode-off mode=lid-closed reason=\(word)")
        }
    }

    // MARK: Wake on schedule

    func testScheduleEventsAreStoredAndReadBack() throws {
        let log = makeLog()
        let events: [ActivityEvent] = [
            .scheduledWake,
            .modeOnBySchedule(.lidClosed),
            .modeSkipped(.lidClosed, .notOnPower),
            .modeSkipped(.lidClosed, .error("The helper did not respond.")),
        ]
        for (index, event) in events.enumerated() {
            log.record(event, at: at(TimeInterval(index)))
        }
        XCTAssertEqual(ActivityLog.read(from: fileURL).map(\.event), events)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        XCTAssertEqual(object?["version"] as? Int, 1)
        let entries = try XCTUnwrap(object?["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["kind"] as? String }, ["wake", "mode-on", "mode-skipped", "mode-skipped"])
        XCTAssertEqual(entries[0]["by"] as? String, "schedule")
        XCTAssertEqual(entries[1]["by"] as? String, "schedule")
        XCTAssertEqual(entries[1]["mode"] as? String, "lid-closed")
        XCTAssertEqual(entries[2]["reason"] as? String, "not-on-power")
        XCTAssertNil(entries[2]["message"])
        XCTAssertEqual(entries[3]["reason"] as? String, "error")
        XCTAssertEqual(entries[3]["message"] as? String, "The helper did not respond.")
    }

    func testOldFileWithoutScheduleFieldsReadsAsBefore() throws {
        try writeFile("""
        {"version": 1, "entries": [
          {"kind": "sleep", "time": 1800000000},
          {"kind": "wake", "time": 1800000010},
          {"kind": "mode-on", "time": 1800000020, "mode": "lid-closed"},
          {"kind": "mode-off", "time": 1800000030, "mode": "lid-closed", "reason": "user"}
        ]}
        """)

        XCTAssertEqual(makeLog().entries, [
            ActivityEntry(time: at(0), event: .sleep),
            ActivityEntry(time: at(10), event: .wake),
            ActivityEntry(time: at(20), event: .modeOn(.lidClosed)),
            ActivityEntry(time: at(30), event: .modeOff(.lidClosed, .user)),
        ])
    }

    func testDamagedScheduleEntriesAreSkipped() throws {
        try writeFile("""
        {"version": 1, "entries": [
          {"kind": "mode-skipped", "time": 1800000000, "mode": "lid-closed", "reason": "later-reason"},
          {"kind": "mode-skipped", "time": 1800000010, "mode": "lid-closed"},
          {"kind": "mode-skipped", "time": 1800000020, "mode": "lid-closed", "reason": "error"},
          {"kind": "wake", "time": 1800000030, "by": "someone-later"}
        ]}
        """)

        XCTAssertEqual(makeLog().entries, [
            ActivityEntry(time: at(20), event: .modeSkipped(.lidClosed, .error(""))),
            ActivityEntry(time: at(30), event: .wake),
        ])
    }

    func testPrintedScheduleLines() {
        let zone = TimeZone(secondsFromGMT: 7200)!
        let time = ISO8601DateFormatter().date(from: "2026-10-11T22:10:03Z")!
        func line(_ event: ActivityEvent) -> String {
            ActivityToken.line(for: ActivityEntry(time: time, event: event), timeZone: zone)
        }

        let stamp = "2026-10-12T00:10:03+02:00"
        XCTAssertEqual(line(.scheduledWake), "\(stamp) wake by=schedule")
        XCTAssertEqual(line(.modeOnBySchedule(.lidClosed)), "\(stamp) mode-on mode=lid-closed by=schedule")
        XCTAssertEqual(
            line(.modeSkipped(.lidClosed, .notOnPower)),
            "\(stamp) mode-skipped mode=lid-closed reason=not-on-power"
        )
        XCTAssertEqual(
            line(.modeSkipped(.lidClosed, .error("Say \"hi\""))),
            "\(stamp) mode-skipped mode=lid-closed reason=error message=\"Say \\\"hi\\\"\""
        )
    }

    func testMissedWakeIsStoredAndPrinted() throws {
        let log = makeLog()
        log.record(.modeSkipped(.lidClosed, .missed), at: at(0))
        XCTAssertEqual(ActivityLog.read(from: fileURL).map(\.event), [.modeSkipped(.lidClosed, .missed)])

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let entry = try XCTUnwrap((object?["entries"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["kind"] as? String, "mode-skipped")
        XCTAssertEqual(entry["reason"] as? String, "missed")
        XCTAssertNil(entry["message"])

        let time = ISO8601DateFormatter().date(from: "2026-10-12T12:19:00Z")!
        XCTAssertEqual(
            ActivityToken.line(
                for: ActivityEntry(time: time, event: .modeSkipped(.lidClosed, .missed)),
                timeZone: TimeZone(secondsFromGMT: 7200)!
            ),
            "2026-10-12T14:19:00+02:00 mode-skipped mode=lid-closed reason=missed"
        )
    }
}

private final class FakeSleepMonitor: SystemSleepMonitoring {
    private var handler: ((Bool) -> Void)?

    func start(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func change(asleep: Bool) {
        handler?(asleep)
    }
}

@MainActor
final class SystemSleepRecorderTests: XCTestCase {
    func testSleepAndWakeAreRecorded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SleepRecorderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let log = ActivityLog(fileURL: folder.appendingPathComponent("activity-log.json"), now: { clock })
        let monitor = FakeSleepMonitor()
        let recorder = SystemSleepRecorder(monitor: monitor, log: log)

        monitor.change(asleep: true)
        XCTAssertEqual(log.entries, [], "nothing is recorded before start")

        recorder.start()
        monitor.change(asleep: true)
        clock += 3600
        monitor.change(asleep: false)
        XCTAssertEqual(log.entries, [
            ActivityEntry(time: Date(timeIntervalSince1970: 1_800_000_000), event: .sleep),
            ActivityEntry(time: Date(timeIntervalSince1970: 1_800_003_600), event: .wake),
        ])
    }
}
