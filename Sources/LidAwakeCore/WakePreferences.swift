import Combine
import Foundation
import LidAwakeShared

/// The daily wake: whether it is on and the local time it happens at.
@MainActor
public final class WakePreferences: ObservableObject {
    public enum Key {
        public static let wakeEnabled = "wakeEnabled"
        public static let wakeMinuteOfDay = "wakeMinuteOfDay"
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

    /// The value for the helper's `setScheduledWake`.
    public var helperMinuteOfDay: Int {
        wakeEnabled ? wakeMinuteOfDay : ScheduledWake.off
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        changes.send()
    }
}
