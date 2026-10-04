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

/// A message about the helper after Run with Lid Closed was chosen, with the action it offers.
public enum HelperPrompt: Equatable {
    case approval
    case moveToApplications
    case failed(String)

    public enum Action: Equatable {
        case openSystemSettings
        case tryAgain
    }

    public var message: String {
        switch self {
        case .approval:
            return String(localized: "Allow LidAwake in System Settings > General > Login Items & Extensions.")
        case .moveToApplications:
            return String(localized: "Move LidAwake to the Applications folder to use Run with Lid Closed.")
        case .failed(let message):
            return message
        }
    }

    public var action: Action? {
        switch self {
        case .approval: return .openSystemSettings
        case .moveToApplications: return nil
        case .failed: return .tryAgain
        }
    }

    public var actionTitle: String? {
        switch action {
        case .openSystemSettings: return String(localized: "Open System Settings")
        case .tryAgain: return String(localized: "Try Again")
        case nil: return nil
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
