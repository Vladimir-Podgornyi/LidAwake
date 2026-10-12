import IOKit.pwr_mgt
import XCTest
@testable import LidAwakeHelperKit
import LidAwakeShared

private let notPrivileged: Int32 = -536_870_207 // kIOReturnNotPrivileged, 0xE00002C1

private final class FakePowerEvents: PowerEventScheduling {
    var list: [PowerEvent]
    var readFails = false
    var failingWakes: Set<Date> = []
    private(set) var scheduled: [Date] = []
    private(set) var cancelled: [Date] = []

    init(_ list: [PowerEvent] = []) {
        self.list = list
    }

    func events() throws -> [PowerEvent] {
        if readFails { throw WakeScheduleError.unreadable }
        return list
    }

    func scheduleWake(at time: Date) throws {
        if failingWakes.contains(time) { throw WakeScheduleError.scheduleFailed(time, notPrivileged) }
        scheduled.append(time)
        list.append(ours(time))
    }

    func cancelWake(at time: Date) throws {
        cancelled.append(time)
        list.removeAll { WakeSchedule.isOurs($0) && $0.time == time }
    }
}

private func ours(_ time: Date) -> PowerEvent {
    PowerEvent(time: time, owner: HelperConstants.helperIdentifier, type: "wake")
}

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func local(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

final class WakeScheduleTests: XCTestCase {
    private func scheduler(_ events: FakePowerEvents, now: Date) -> WakeScheduler {
        WakeScheduler(events: events, now: { now }, calendar: { berlin })
    }

    func testBeforeTheTimeSchedulesTodayAndTomorrow() {
        let events = FakePowerEvents()
        XCTAssertEqual(scheduler(events, now: local(10, 12, 7, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [local(10, 12, 8, 0), local(10, 13, 8, 0)])
        XCTAssertEqual(events.cancelled, [])
    }

    func testAfterTheTimeSchedulesTomorrowAndTheDayAfter() {
        let events = FakePowerEvents()
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [local(10, 13, 8, 0), local(10, 14, 8, 0)])
    }

    func testTimeWithinAMinuteMovesToTomorrow() {
        let events = FakePowerEvents()
        XCTAssertEqual(scheduler(events, now: local(10, 12, 7, 59, 30)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [local(10, 13, 8, 0), local(10, 14, 8, 0)])
    }

    func testMatchingScheduleChangesNothing() {
        let events = FakePowerEvents([ours(local(10, 12, 8, 0)), ours(local(10, 13, 8, 0))])
        XCTAssertEqual(scheduler(events, now: local(10, 12, 7, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [])
        XCTAssertEqual(events.cancelled, [])
    }

    func testOldTimeIsReplaced() {
        let events = FakePowerEvents([ours(local(10, 13, 7, 0)), ours(local(10, 14, 7, 0))])
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.cancelled, [local(10, 13, 7, 0), local(10, 14, 7, 0)])
        XCTAssertEqual(events.scheduled, [local(10, 13, 8, 0), local(10, 14, 8, 0)])
        XCTAssertEqual(try scheduler(events, now: local(10, 12, 9, 0)).scheduledWakes(), [local(10, 13, 8, 0), local(10, 14, 8, 0)])
    }

    func testMissingWakeIsAdded() {
        let events = FakePowerEvents([ours(local(10, 13, 8, 0))])
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [local(10, 14, 8, 0)])
        XCTAssertEqual(events.cancelled, [])
    }

    func testOffCancelsOursOnly() {
        let foreign = [
            PowerEvent(time: local(10, 13, 8, 0), owner: "pmset", type: "wake"),
            PowerEvent(time: local(10, 13, 9, 0), owner: "com.example.other", type: "wake"),
        ]
        let events = FakePowerEvents(foreign + [ours(local(10, 13, 8, 0)), ours(local(10, 14, 8, 0))])
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: ScheduledWake.off), .ok)
        XCTAssertEqual(events.cancelled, [local(10, 13, 8, 0), local(10, 14, 8, 0)])
        XCTAssertEqual(events.scheduled, [])
        XCTAssertEqual(events.list, foreign)
    }

    func testForeignEventsAreNeitherCancelledNorCounted() {
        let foreign = [
            PowerEvent(time: local(10, 13, 8, 0), owner: "pmset", type: "wake"),
            PowerEvent(time: local(10, 14, 8, 0), owner: HelperConstants.helperIdentifier, type: "wakepoweron"),
            PowerEvent(time: local(10, 13, 7, 0), owner: HelperConstants.helperIdentifier, type: "shutdown"),
            PowerEvent(time: local(10, 13, 7, 0), owner: "pmset", type: "poweron"),
        ]
        let events = FakePowerEvents(foreign)
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60), .ok)
        XCTAssertEqual(events.scheduled, [local(10, 13, 8, 0), local(10, 14, 8, 0)])
        XCTAssertEqual(events.cancelled, [])
        XCTAssertEqual(Array(events.list.prefix(foreign.count)), foreign)
        XCTAssertEqual(try scheduler(events, now: local(10, 12, 9, 0)).scheduledWakes(), [local(10, 13, 8, 0), local(10, 14, 8, 0)])
    }

    func testSkippedTimeMovesToTheFirstMinuteAfterTheChange() {
        // 29 March 2026: the clocks go from 02:00 straight to 03:00 CEST.
        let wakes = WakeSchedule.wakes(minuteOfDay: 2 * 60 + 30, after: local(3, 28, 12, 0), calendar: berlin)
        XCTAssertEqual(wakes, [utc("2026-03-29T01:00:00Z"), utc("2026-03-30T00:30:00Z")])
    }

    func testRepeatedTimeTakesTheFirstOccurrence() {
        // 25 October 2026: the clocks go from 03:00 CEST back to 02:00 CET.
        let wakes = WakeSchedule.wakes(minuteOfDay: 2 * 60 + 30, after: local(10, 24, 12, 0), calendar: berlin)
        XCTAssertEqual(wakes, [utc("2026-10-25T00:30:00Z"), utc("2026-10-26T01:30:00Z")])
    }

    func testMinuteOutOfRangeIsRejected() {
        let events = FakePowerEvents()
        for minute in [1440, -2] {
            XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: minute).code, .invalidArgument, "\(minute)")
        }
        XCTAssertEqual(events.scheduled, [])
        XCTAssertEqual(events.cancelled, [])
    }

    func testFailedWakeKeepsTheOneAlreadyScheduled() {
        let events = FakePowerEvents([ours(local(10, 13, 7, 0))])
        events.failingWakes = [local(10, 14, 8, 0)]
        let result = scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60)
        XCTAssertEqual(result.code, .wakeScheduleFailed)
        XCTAssertTrue(result.message?.contains("0xE00002C1") == true, result.message ?? "")
        XCTAssertTrue(result.message?.contains("-536870207") == true, result.message ?? "")
        XCTAssertEqual(events.scheduled, [local(10, 13, 8, 0)])
        XCTAssertFalse(events.cancelled.contains(local(10, 13, 8, 0)))
        XCTAssertTrue(events.list.contains(ours(local(10, 13, 8, 0))))
    }

    func testUnreadableEventsChangeNothing() {
        let events = FakePowerEvents()
        events.readFails = true
        XCTAssertEqual(scheduler(events, now: local(10, 12, 9, 0)).set(minuteOfDay: 8 * 60).code, .wakeScheduleFailed)
        XCTAssertEqual(events.scheduled, [])
        XCTAssertThrowsError(try scheduler(events, now: local(10, 12, 9, 0)).scheduledWakes())
    }

    func testWakeTypeIsTheSystemOne() {
        XCTAssertEqual(WakeSchedule.wakeType, kIOPMAutoWake)
        XCTAssertEqual(WakeSchedule.owner, "com.vladimirpodgornyi.LidAwake.helper")
    }
}
