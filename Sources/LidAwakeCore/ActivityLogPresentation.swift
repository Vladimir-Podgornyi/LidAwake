import Foundation
import LidAwakeShared

/// The symbol drawn before an entry in the log window.
public enum ActivitySymbol: Equatable, CaseIterable {
    case modeOn
    case modeOff
    case paused
    case resumed
    case busy
    case idle
    case sleep
    case wake

    public var systemName: String {
        switch self {
        case .modeOn: return "circle.fill"
        case .modeOff: return "circle"
        case .paused: return "pause.fill"
        case .resumed: return "play.fill"
        case .busy: return "bolt.fill"
        case .idle: return "clock"
        case .sleep: return "moon.fill"
        case .wake: return "sun.max.fill"
        }
    }

    /// Drawn in the accent color; the rest in the secondary text color.
    public var usesAccent: Bool {
        switch self {
        case .modeOn, .resumed, .busy: return true
        case .modeOff, .paused, .idle, .sleep, .wake: return false
        }
    }
}

/// An entry as the log window shows it, worded in the language of the interface.
public struct ActivityRow: Equatable {
    public let title: String
    public let detail: String?
    public let symbol: ActivitySymbol

    public init(title: String, detail: String?, symbol: ActivitySymbol) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    public init(_ entry: ActivityEntry) {
        switch entry.event {
        case .modeOn(let mode):
            self.init(title: Self.modeOnTitle(mode), detail: String(localized: "By you"), symbol: .modeOn)
        case .modeOff(let mode, let reason):
            self.init(title: Self.modeOffTitle(mode), detail: Self.text(for: reason, at: entry.time), symbol: .modeOff)
        case .paused:
            self.init(title: String(localized: "Paused"), detail: String(localized: "Running on battery"), symbol: .paused)
        case .resumed:
            self.init(title: String(localized: "Resumed"), detail: String(localized: "Power connected"), symbol: .resumed)
        case .keptAwakeByApp(let name):
            self.init(
                title: String(localized: "Kept awake by \(name)"),
                detail: String(localized: "The app asked macOS not to sleep."),
                symbol: .busy
            )
        case .keptAwakeByLoad(let busiest):
            let name = busiest?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(
                title: String(localized: "Kept awake by CPU load"),
                detail: name.flatMap { $0.isEmpty ? nil : String(localized: "Busiest app: \($0)") },
                symbol: .busy
            )
        case .keptAwakeByInput:
            self.init(title: String(localized: "Kept awake by keyboard or mouse"), detail: nil, symbol: .busy)
        case .idleStarted(let minutes):
            self.init(
                title: String(localized: "Idle"),
                detail: String(localized: "No work detected, counting \(minutes) minutes"),
                symbol: .idle
            )
        case .sleep:
            self.init(title: String(localized: "Mac went to sleep"), detail: nil, symbol: .sleep)
        case .wake:
            self.init(title: String(localized: "Mac woke up"), detail: nil, symbol: .wake)
        }
    }

    // Off is never turned on or off by itself, so it shares the wording of Run with Lid Closed.
    private static func modeOnTitle(_ mode: Mode) -> String {
        switch mode {
        case .keepScreenOn: return String(localized: "Keep Screen On turned on")
        case .lidClosed, .off: return String(localized: "Run with Lid Closed turned on")
        }
    }

    private static func modeOffTitle(_ mode: Mode) -> String {
        switch mode {
        case .keepScreenOn: return String(localized: "Keep Screen On turned off")
        case .lidClosed, .off: return String(localized: "Run with Lid Closed turned off")
        }
    }

    /// The same words as the stop notification, so the log and the banner agree.
    static func text(for reason: ModeOffReason, at time: Date) -> String {
        switch reason {
        case .user:
            return String(localized: "By you")
        case .stopped(.timer, _, _, let timerSeconds?):
            return String(localized: "The timer ended after \(DurationFormat.choice(timerSeconds)).")
        case .stopped(let stop, let battery, let idle, _):
            return StopNotice.body(for: StopRecord(reason: stop, time: time, batteryPercent: battery, idleMinutes: idle))
        case .error(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Something went wrong") : trimmed
        case .previousSession:
            return String(localized: "LidAwake was restarted.")
        }
    }
}

/// The heading of a day in the log window.
public enum ActivityDayTitle: Equatable {
    case today
    case yesterday
    /// The start of the day.
    case date(Date)

    /// The year is added only for a day of another year.
    public func text(now: Date, calendar: Calendar, locale: Locale) -> String {
        switch self {
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case .date(let day):
            let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "dMMMM" : "dMMMMy")
            return formatter.string(from: day)
        }
    }
}

public struct ActivityDay: Equatable {
    public let title: ActivityDayTitle
    /// Newest first.
    public let entries: [ActivityEntry]

    public init(title: ActivityDayTitle, entries: [ActivityEntry]) {
        self.title = title
        self.entries = entries
    }

    /// Groups the log by day, newest day and newest entry first. Entries that happened at the same
    /// moment keep the reverse of their order in the log.
    public static func list(_ entries: [ActivityEntry], now: Date, calendar: Calendar) -> [ActivityDay] {
        let newestFirst = entries.enumerated()
            .sorted { $0.element.time != $1.element.time ? $0.element.time > $1.element.time : $0.offset > $1.offset }
            .map(\.element)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var days: [ActivityDay] = []
        var current: (start: Date, entries: [ActivityEntry])?
        func flush() {
            guard let current else { return }
            let title: ActivityDayTitle
            if current.start == today {
                title = .today
            } else if current.start == yesterday {
                title = .yesterday
            } else {
                title = .date(current.start)
            }
            days.append(ActivityDay(title: title, entries: current.entries))
        }
        for entry in newestFirst {
            let start = calendar.startOfDay(for: entry.time)
            if current?.start == start {
                current?.entries.append(entry)
            } else {
                flush()
                current = (start, [entry])
            }
        }
        flush()
        return days
    }
}
