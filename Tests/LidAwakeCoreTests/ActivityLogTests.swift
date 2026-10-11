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

        let reasons: [(StopReason, String)] = [
            (.timer, "timer"), (.battery, "battery"), (.batteryUnreadable, "battery-unreadable"),
            (.thermal, "thermal"), (.thermalUnreadable, "thermal-unreadable"),
            (.powerUnreadable, "power-unreadable"), (.leaseExpired, "lease-expired"), (.idle, "idle"),
        ]
        for (reason, word) in reasons {
            XCTAssertEqual(line(.modeOff(.lidClosed, .stopped(reason))), "\(stamp) mode-off mode=lid-closed reason=\(word)")
        }
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
