import Combine
import Foundation
import LidAwakeShared

/// The daily wake: whether it is on and the local time it happens at.
@MainActor
public final class WakePreferences: ObservableObject {
    public enum Key {
        public static let wakeEnabled = "wakeEnabled"
        public static let wakeMinuteOfDay = "wakeMinuteOfDay"
        public static let scheduledWakeTimes = "scheduledWakeTimes"
    }

    public static let defaultMinuteOfDay = 480

    @Published public var wakeEnabled: Bool {
        didSet { save(wakeEnabled, Key.wakeEnabled) }
    }
    /// 0 to 1439, local time.
    @Published public var wakeMinuteOfDay: Int {
        didSet { save(wakeMinuteOfDay, Key.wakeMinuteOfDay) }
    }

    /// Fires after either setting has changed.
    public let changes = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.wakeEnabled: false,
            Key.wakeMinuteOfDay: Self.defaultMinuteOfDay,
        ])
        wakeEnabled = defaults.bool(forKey: Key.wakeEnabled)
        let minute = defaults.integer(forKey: Key.wakeMinuteOfDay)
        wakeMinuteOfDay = ScheduledWake.minutes.contains(minute) ? minute : Self.defaultMinuteOfDay
    }

    /// The wakes the helper reported last, kept so a wake missed before a restart can still be found.
    /// Saving them does not fire `changes`.
    public var scheduledWakeTimes: [Date] {
        get { defaults.array(forKey: Key.scheduledWakeTimes)?.compactMap { $0 as? Date } ?? [] }
        set { defaults.set(newValue, forKey: Key.scheduledWakeTimes) }
    }

    /// The value for the helper's `setScheduledWake`.
    public var helperMinuteOfDay: Int {
        wakeEnabled ? wakeMinuteOfDay : ScheduledWake.off
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        changes.send()
    }
}

/// What the Wake at row shows.
public enum WakeRow {
    public enum Detail: Equatable {
        case everyDay
        case couldNotSet
    }

    /// The text under the title: the failure of the last agreement with the helper, or the usual one.
    public static func detail(lastError: String?) -> Detail {
        lastError == nil ? .everyDay : .couldNotSet
    }

    /// The time in the pill, in the 12- or 24-hour form the system uses.
    public static func time(minuteOfDay: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minuteOfDay * 60)))
    }

    /// A date at the minute of the day, for the time picker. The day is fixed, away from any
    /// daylight saving change, so every minute exists on it.
    public static func date(minuteOfDay: Int, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: TimeInterval(minuteOfDay * 60))
    }

    public static func minuteOfDay(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
