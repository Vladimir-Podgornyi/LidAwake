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
