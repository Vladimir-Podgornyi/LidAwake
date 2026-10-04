import Combine
import Foundation
import LidAwakeShared

@MainActor
public final class SafetyPreferences: ObservableObject {
    public enum Key {
        public static let timerEnabled = "timerEnabled"
        public static let timerSeconds = "timerSeconds"
        public static let batteryLimitEnabled = "batteryLimitEnabled"
        public static let batteryLimitPercent = "batteryLimitPercent"
        public static let thermalProtectionEnabled = "thermalProtectionEnabled"
        public static let chargingOnlyEnabled = "chargingOnlyEnabled"
        public static let lockOnLidCloseEnabled = "lockOnLidCloseEnabled"
    }

    public static let timerChoices = [1800, 3600, 7200, 14_400, 28_800]
    public static let batteryLimitChoices = [10, 20, 30, 40, 50]

    @Published public var timerEnabled: Bool {
        didSet { save(timerEnabled, Key.timerEnabled) }
    }
    @Published public var timerSeconds: Int {
        didSet { save(timerSeconds, Key.timerSeconds) }
    }
    @Published public var batteryLimitEnabled: Bool {
        didSet { save(batteryLimitEnabled, Key.batteryLimitEnabled) }
    }
    @Published public var batteryLimitPercent: Int {
        didSet { save(batteryLimitPercent, Key.batteryLimitPercent) }
    }
    @Published public var thermalProtectionEnabled: Bool {
        didSet { save(thermalProtectionEnabled, Key.thermalProtectionEnabled) }
    }
    @Published public var chargingOnlyEnabled: Bool {
        didSet { save(chargingOnlyEnabled, Key.chargingOnlyEnabled) }
    }
    /// Not sent to the helper, so changing it does not fire `changes`.
    @Published public var lockOnLidCloseEnabled: Bool {
        didSet { defaults.set(lockOnLidCloseEnabled, forKey: Key.lockOnLidCloseEnabled) }
    }

    /// Fires after any setting has changed.
    public let changes = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.timerEnabled: false,
            Key.timerSeconds: 7200,
            Key.batteryLimitEnabled: true,
            Key.batteryLimitPercent: 20,
            Key.thermalProtectionEnabled: true,
            Key.chargingOnlyEnabled: false,
            Key.lockOnLidCloseEnabled: true,
        ])
        timerEnabled = defaults.bool(forKey: Key.timerEnabled)
        timerSeconds = Self.clamp(defaults.integer(forKey: Key.timerSeconds), to: SafetySettings.timerRange)
        batteryLimitEnabled = defaults.bool(forKey: Key.batteryLimitEnabled)
        batteryLimitPercent = Self.clamp(
            defaults.integer(forKey: Key.batteryLimitPercent),
            to: SafetySettings.batteryLimitRange
        )
        thermalProtectionEnabled = defaults.bool(forKey: Key.thermalProtectionEnabled)
        chargingOnlyEnabled = defaults.bool(forKey: Key.chargingOnlyEnabled)
        lockOnLidCloseEnabled = defaults.bool(forKey: Key.lockOnLidCloseEnabled)
    }

    /// The timer applies in both modes; the other protections only in Run with Lid Closed.
    public var timerLimit: Int? {
        timerEnabled ? timerSeconds : nil
    }

    public var helperSettings: SafetySettings {
        SafetySettings(
            timerSeconds: timerEnabled ? timerSeconds : 0,
            batteryLimitPercent: batteryLimitEnabled ? batteryLimitPercent : 0,
            thermalProtection: thermalProtectionEnabled,
            chargingOnly: chargingOnlyEnabled
        )
    }

    /// A stored value the helper would reject is read as the nearest one it accepts.
    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        changes.send()
    }
}
