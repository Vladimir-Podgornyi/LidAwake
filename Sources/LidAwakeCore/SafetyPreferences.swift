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
        ])
        timerEnabled = defaults.bool(forKey: Key.timerEnabled)
        timerSeconds = defaults.integer(forKey: Key.timerSeconds)
        batteryLimitEnabled = defaults.bool(forKey: Key.batteryLimitEnabled)
        batteryLimitPercent = defaults.integer(forKey: Key.batteryLimitPercent)
        thermalProtectionEnabled = defaults.bool(forKey: Key.thermalProtectionEnabled)
        chargingOnlyEnabled = defaults.bool(forKey: Key.chargingOnlyEnabled)
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

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        changes.send()
    }
}
