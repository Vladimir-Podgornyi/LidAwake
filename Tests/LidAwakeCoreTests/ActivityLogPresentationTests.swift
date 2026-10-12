import LidAwakeShared
import XCTest
@testable import LidAwakeCore

final class ActivityRowTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(_ event: ActivityEvent) -> ActivityRow {
        ActivityRow(ActivityEntry(time: time, event: event))
    }

    private func offDetail(_ reason: ModeOffReason) -> String? {
        row(.modeOff(.lidClosed, reason)).detail
    }

    // MARK: Events

    func testModeOn() {
        XCTAssertEqual(
            row(.modeOn(.lidClosed)),
            ActivityRow(title: "Run with Lid Closed turned on", detail: "By you", symbol: .modeOn)
        )
        XCTAssertEqual(
            row(.modeOn(.keepScreenOn)),
            ActivityRow(title: "Keep Screen On turned on", detail: "By you", symbol: .modeOn)
        )
    }

    func testModeOff() {
        XCTAssertEqual(
            row(.modeOff(.lidClosed, .user)),
            ActivityRow(title: "Run with Lid Closed turned off", detail: "By you", symbol: .modeOff)
        )
        XCTAssertEqual(
            row(.modeOff(.keepScreenOn, .user)),
            ActivityRow(title: "Keep Screen On turned off", detail: "By you", symbol: .modeOff)
        )
    }

    func testPausedAndResumed() {
        XCTAssertEqual(row(.paused), ActivityRow(title: "Paused", detail: "Running on battery", symbol: .paused))
        XCTAssertEqual(row(.resumed), ActivityRow(title: "Resumed", detail: "Power connected", symbol: .resumed))
    }

    func testKeptAwakeByApp() {
        XCTAssertEqual(
            row(.keptAwakeByApp("Example App")),
            ActivityRow(title: "Kept awake by Example App", detail: "The app asked macOS not to sleep.", symbol: .busy)
        )
    }

    func testKeptAwakeByLoadWithTheBusiestProcess() {
        XCTAssertEqual(
            row(.keptAwakeByLoad(busiest: "example-tool")),
            ActivityRow(title: "Kept awake by CPU load", detail: "Busiest app: example-tool", symbol: .busy)
        )
    }

    func testKeptAwakeByLoadWithoutAName() {
        let expected = ActivityRow(title: "Kept awake by CPU load", detail: nil, symbol: .busy)
        XCTAssertEqual(row(.keptAwakeByLoad(busiest: nil)), expected)
        XCTAssertEqual(row(.keptAwakeByLoad(busiest: " ")), expected)
    }

    func testKeptAwakeByInput() {
        XCTAssertEqual(
            row(.keptAwakeByInput),
            ActivityRow(title: "Kept awake by keyboard or mouse", detail: nil, symbol: .busy)
        )
    }

    func testIdleStarted() {
        XCTAssertEqual(
            row(.idleStarted(minutes: 20)),
            ActivityRow(title: "Idle", detail: "No work detected, counting 20 minutes", symbol: .idle)
        )
    }

    func testSleepAndWake() {
        XCTAssertEqual(row(.sleep), ActivityRow(title: "Mac went to sleep", detail: nil, symbol: .sleep))
        XCTAssertEqual(row(.wake), ActivityRow(title: "Mac woke up", detail: nil, symbol: .wake))
    }

    // MARK: Why a mode turned off

    func testTimerWithItsLength() {
        XCTAssertEqual(offDetail(.stopped(.timer, timerSeconds: 14_400)), "The timer ended after 4 hours.")
        XCTAssertEqual(offDetail(.stopped(.timer, timerSeconds: 4800)), "The timer ended after 1 h 20 min.")
        XCTAssertEqual(
            row(.modeOff(.keepScreenOn, .stopped(.timer, timerSeconds: 1800))).detail,
            "The timer ended after 30 min."
        )
    }

    func testTimerWithoutItsLength() {
        XCTAssertEqual(offDetail(.stopped(.timer)), "The timer ran out.")
    }

    func testStopsUseTheNotificationText() {
        let reasons: [ModeOffReason] = [
            .stopped(.battery, batteryPercent: 18),
            .stopped(.battery),
            .stopped(.batteryUnreadable),
            .stopped(.thermal),
            .stopped(.thermalUnreadable),
            .stopped(.powerUnreadable),
            .stopped(.leaseExpired),
            .stopped(.idle, idleMinutes: 20),
            .stopped(.idle),
        ]
        let expected = [
            "The battery dropped to 18%.",
            "The battery dropped below the limit.",
            "The battery level could not be read.",
            "The Mac got too hot.",
            "The thermal state could not be read.",
            "The power source could not be read.",
            "LidAwake closed unexpectedly, so normal sleep was restored.",
            "Nothing was working for 20 minutes.",
            "Nothing was working for a while.",
        ]
        XCTAssertEqual(reasons.map(offDetail), expected)
        for case .stopped(let stop, let battery, let idle, _) in reasons {
            let record = StopRecord(reason: stop, time: time, batteryPercent: battery, idleMinutes: idle)
            XCTAssertEqual(offDetail(.stopped(stop, batteryPercent: battery, idleMinutes: idle)), StopNotice.body(for: record))
        }
    }

    func testErrorWithText() {
        XCTAssertEqual(offDetail(.error("The helper did not respond.")), "The helper did not respond.")
    }

    func testErrorWithoutText() {
        XCTAssertEqual(offDetail(.error("")), "Something went wrong")
        XCTAssertEqual(offDetail(.error("  \n")), "Something went wrong")
    }

    func testPreviousSession() {
        XCTAssertEqual(offDetail(.previousSession), "LidAwake was restarted.")
    }

    func testScheduleEvents() {
        XCTAssertEqual(
            row(.scheduledWake),
            ActivityRow(title: "Mac woke up", detail: "On schedule", symbol: .wake)
        )
        XCTAssertEqual(
            row(.modeOnBySchedule(.lidClosed)),
            ActivityRow(title: "Run with Lid Closed turned on", detail: "On schedule", symbol: .modeOn)
        )
        XCTAssertEqual(
            row(.modeSkipped(.lidClosed, .notOnPower)),
            ActivityRow(title: "Run with Lid Closed not turned on", detail: "Not on power", symbol: .skipped)
        )
        XCTAssertEqual(
            row(.modeSkipped(.lidClosed, .error(" The helper did not respond.\n"))),
            ActivityRow(title: "Run with Lid Closed not turned on", detail: "The helper did not respond.", symbol: .skipped)
        )
        XCTAssertEqual(row(.modeSkipped(.lidClosed, .error(""))).detail, "Something went wrong")
    }

    // MARK: Symbols

    func testSymbolOfEveryEvent() {
        let events: [(ActivityEvent, ActivitySymbol)] = [
            (.modeOn(.lidClosed), .modeOn),
            (.modeOn(.keepScreenOn), .modeOn),
            (.modeOff(.lidClosed, .stopped(.thermal)), .modeOff),
            (.modeOff(.keepScreenOn, .error("")), .modeOff),
            (.paused, .paused),
            (.resumed, .resumed),
            (.keptAwakeByApp("Example App"), .busy),
            (.keptAwakeByLoad(busiest: nil), .busy),
            (.keptAwakeByInput, .busy),
            (.idleStarted(minutes: 10), .idle),
            (.sleep, .sleep),
            (.wake, .wake),
        ]
        for (event, symbol) in events {
            XCTAssertEqual(row(event).symbol, symbol, "\(event)")
        }
    }

    func testSymbolShapesAndColors() {
        let expected: [ActivitySymbol: (String, Bool)] = [
            .modeOn: ("circle.fill", true),
            .modeOff: ("circle", false),
            .skipped: ("circle.slash", false),
            .paused: ("pause.fill", false),
            .resumed: ("play.fill", true),
            .busy: ("bolt.fill", true),
            .idle: ("clock", false),
            .sleep: ("moon.fill", false),
            .wake: ("sun.max.fill", false),
        ]
        XCTAssertEqual(Set(expected.keys), Set(ActivitySymbol.allCases))
        for symbol in ActivitySymbol.allCases {
            XCTAssertEqual(symbol.systemName, expected[symbol]?.0, "\(symbol)")
            XCTAssertEqual(symbol.usesAccent, expected[symbol]?.1, "\(symbol)")
        }
    }
}

final class ActivityDayTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func at(month: Int = 10, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ time: Date, _ event: ActivityEvent = .wake) -> ActivityEntry {
        ActivityEntry(time: time, event: event)
    }

    func testTodayYesterdayAndAnEarlierDate() {
        let entries = [
            entry(at(9, 23, 50), .sleep),
            entry(at(10, 0, 10), .wake),
            entry(at(11, 22, 0), .sleep),
            entry(at(12, 7, 30), .wake),
            entry(at(12, 8, 0), .modeOn(.lidClosed)),
        ]
        let days = ActivityDay.list(entries, now: at(12, 15, 40), calendar: calendar)
        XCTAssertEqual(days, [
            ActivityDay(title: .today, entries: [entries[4], entries[3]]),
            ActivityDay(title: .yesterday, entries: [entries[2]]),
            ActivityDay(title: .date(at(10, 0)), entries: [entries[1]]),
            ActivityDay(title: .date(at(9, 0)), entries: [entries[0]]),
        ])
    }

    func testNewestFirstWithinADay() {
        let entries = [
            entry(at(12, 8, 0), .modeOn(.lidClosed)),
            entry(at(12, 9, 0), .keptAwakeByInput),
            entry(at(12, 9, 0), .idleStarted(minutes: 20)),
            entry(at(12, 9, 20), .modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20))),
        ]
        let days = ActivityDay.list(entries, now: at(12, 10), calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.entries, [entries[3], entries[2], entries[1], entries[0]])
    }

    func testMidnightBelongsToTheNewDay() {
        let days = ActivityDay.list([entry(at(11, 23, 59)), entry(at(12, 0, 0))], now: at(12, 0, 30), calendar: calendar)
        XCTAssertEqual(days.map(\.title), [.today, .yesterday])
    }

    func testDaysFollowTheCalendarTimeZone() {
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 20:00 in Berlin on the 11th is 03:00 on the 12th in Tokyo.
        let days = ActivityDay.list([entry(at(11, 20))], now: at(12, 10), calendar: tokyo)
        XCTAssertEqual(days.map(\.title), [.today])
    }

    func testEmptyLog() {
        XCTAssertEqual(ActivityDay.list([], now: at(12, 10), calendar: calendar), [])
    }

    func testTitleTexts() {
        let now = at(12, 15)
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ActivityDayTitle.today.text(now: now, calendar: calendar, locale: english), "Today")
        XCTAssertEqual(ActivityDayTitle.yesterday.text(now: now, calendar: calendar, locale: english), "Yesterday")
        XCTAssertEqual(ActivityDayTitle.date(at(10, 0)).text(now: now, calendar: calendar, locale: english), "October 10")
        XCTAssertEqual(
            ActivityDayTitle.date(at(10, 0)).text(now: now, calendar: calendar, locale: Locale(identifier: "de_DE")),
            "10. Oktober"
        )
    }

    func testDateOfAnotherYearShowsTheYear() {
        let title = ActivityDayTitle.date(at(month: 12, 30, 0, year: 2025))
        XCTAssertEqual(
            title.text(now: at(month: 1, 3, 9, year: 2026), calendar: calendar, locale: Locale(identifier: "en_US")),
            "December 30, 2025"
        )
    }
}
