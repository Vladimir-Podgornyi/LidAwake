import Foundation
import LidAwakeShared

/// Which protections the window offers for a mode.
public enum SafetyLayout: Equatable {
    /// Off and Run with Lid Closed: every protection can be changed.
    case all
    /// Keep Screen On: only the timer applies; the rest is shown dimmed.
    case timerOnly

    public init(mode: Mode) {
        switch mode {
        case .off, .lidClosed: self = .all
        case .keepScreenOn: self = .timerOnly
        }
    }
}

public enum StatusLine {
    /// The text next to the app name; nil when there is nothing to show.
    public static func text(mode: Mode, isPaused: Bool, timerRemaining: TimeInterval?, battery: BatteryLevel) -> String? {
        let timer = timerRemaining.map { String(localized: "\(DurationFormat.remaining(Int($0.rounded(.up)))) left") }
        switch mode {
        case .off:
            return nil
        case .keepScreenOn:
            return timer ?? String(localized: "Screen stays on")
        case .lidClosed:
            if isPaused {
                return String(localized: "Paused · on battery")
            }
            let parts = [timer, batteryText(battery)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private static func batteryText(_ battery: BatteryLevel) -> String? {
        switch battery {
        case .percent(let percent): return String(localized: "Battery \(percent)%")
        case .unknown: return String(localized: "Battery unknown")
        case .none: return nil
        }
    }
}

/// A request for the user to act on the helper; there is none while the helper is ready.
public enum HelperPrompt: Equatable {
    case install(message: String)
    case openSystemSettings(message: String)

    public init?(state: HelperState) {
        switch state {
        case .ready:
            return nil
        case .notInstalled:
            self = .install(message: String(localized: "Run with Lid Closed needs a helper."))
        case .requiresApproval:
            self = .openSystemSettings(
                message: String(localized: "Allow LidAwake in System Settings > General > Login Items & Extensions.")
            )
        case .outdated:
            self = .install(message: String(localized: "The helper is out of date."))
        case .error(let message):
            self = .install(message: String(localized: "Helper error: \(message)"))
        }
    }

    public var message: String {
        switch self {
        case .install(let message), .openSystemSettings(let message): return message
        }
    }

    public var actionTitle: String {
        switch self {
        case .install: return String(localized: "Install Helper")
        case .openSystemSettings: return String(localized: "Open System Settings")
        }
    }
}

public enum DurationFormat {
    /// Whole minutes, rounded up: "45 min", "2 h", "1 h 20 min".
    public static func remaining(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return String(localized: "\(rest) min")
        case (_, 0): return String(localized: "\(hours) h")
        default: return String(localized: "\(hours) h \(rest) min")
        }
    }

    /// The label of a timer choice in the menu.
    public static func choice(_ seconds: Int) -> String {
        switch seconds {
        case 1800: return String(localized: "30 min")
        case 3600: return String(localized: "1 hour")
        case 7200: return String(localized: "2 hours")
        case 14_400: return String(localized: "4 hours")
        case 28_800: return String(localized: "8 hours")
        default: return remaining(seconds)
        }
    }

    public static func percent(_ value: Int) -> String {
        String(localized: "\(value)%")
    }
}
