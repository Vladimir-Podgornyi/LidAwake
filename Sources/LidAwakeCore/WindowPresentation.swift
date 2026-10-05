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

/// How a message in the window looks: what it asks of the user.
public enum MessageKind: Equatable {
    /// The user has to take a step.
    case actionNeeded
    /// Something did not work.
    case error
    /// The app reports what happened.
    case info
}

/// A message about the helper after Run with Lid Closed was chosen, with the action it offers.
public enum HelperPrompt: Equatable {
    case approval
    /// The approval did not come in time and the mode will not start on its own any more.
    case approvalExpired
    case moveToApplications
    case failed(String)

    public enum Action: Equatable {
        case openSystemSettings
        case tryAgain
    }

    public var kind: MessageKind {
        switch self {
        case .approval, .approvalExpired, .moveToApplications: return .actionNeeded
        case .failed: return .error
        }
    }

    public var title: String {
        switch self {
        case .approval, .approvalExpired: return String(localized: "Permission needed")
        case .moveToApplications: return String(localized: "Move LidAwake to Applications")
        case .failed: return String(localized: "The helper did not start")
        }
    }

    public var text: String {
        switch self {
        case .approval:
            return String(
                localized: "Allow LidAwake in System Settings > General > Login Items & Extensions. The mode turns on as soon as you do."
            )
        case .approvalExpired:
            return String(
                localized: "Allow LidAwake in System Settings > General > Login Items & Extensions, then choose Run with Lid Closed again."
            )
        case .moveToApplications:
            return String(localized: "Run with Lid Closed needs the app in the Applications folder.")
        case .failed(let message):
            return message
        }
    }

    public var action: Action? {
        switch self {
        case .approval, .approvalExpired: return .openSystemSettings
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

/// What the mode controller last has to say: a failure or the reason a mode ended.
public enum ModeMessage: Equatable {
    /// A mode was refused: a protection or the helper stood in the way.
    case couldNotTurnOn(String)
    /// A mode ended on its own and the helper or the app gave the reason.
    case turnedOff(String)
    /// Run with Lid Closed ended because the helper stopped answering or failed.
    case turnedOffWithError(String)
    /// The helper failed at something other than starting or keeping a mode.
    case failed(String)
    /// A session left by an earlier run of the app was ended at launch.
    case restarted

    public var kind: MessageKind {
        switch self {
        case .turnedOff, .restarted: return .info
        case .couldNotTurnOn, .turnedOffWithError, .failed: return .error
        }
    }

    public var title: String {
        switch self {
        case .couldNotTurnOn: return String(localized: "Could not turn on")
        case .turnedOff, .turnedOffWithError, .restarted: return String(localized: "LidAwake turned off")
        case .failed: return String(localized: "Something went wrong")
        }
    }

    public var text: String {
        switch self {
        case .couldNotTurnOn(let text), .turnedOff(let text), .turnedOffWithError(let text), .failed(let text):
            return text
        case .restarted:
            return String(localized: "LidAwake was restarted. Turn the mode on again if you need it.")
        }
    }
}

/// One notice in the window's message block.
public struct WindowMessage: Equatable, Identifiable {
    public enum Source: Equatable {
        case helper
        case mode
        case autoLogout
        case update
    }

    public let source: Source
    public let kind: MessageKind
    public let title: String
    public let text: String
    /// A smaller line under the text.
    public let hint: String?
    public let action: HelperPrompt.Action?
    public let actionTitle: String?

    public var id: Source { source }

    /// Only the automatic logout warning can be closed.
    public var isDismissible: Bool { source == .autoLogout }

    /// The notices to show, helper first, then the mode, the logout warning and the update;
    /// empty when there is nothing to say.
    public static func list(
        helper: HelperPrompt?,
        mode: ModeMessage?,
        autoLogout: AutoLogoutNotice? = nil,
        update: UpdateNotice? = nil
    ) -> [WindowMessage] {
        var messages: [WindowMessage] = []
        if let helper {
            messages.append(WindowMessage(
                source: .helper,
                kind: helper.kind,
                title: helper.title,
                text: helper.text,
                hint: nil,
                action: helper.action,
                actionTitle: helper.actionTitle
            ))
        }
        if let mode {
            messages.append(WindowMessage(
                source: .mode,
                kind: mode.kind,
                title: mode.title,
                text: mode.text,
                hint: nil,
                action: nil,
                actionTitle: nil
            ))
        }
        if let autoLogout {
            messages.append(WindowMessage(
                source: .autoLogout,
                kind: .info,
                title: autoLogout.title,
                text: autoLogout.text,
                hint: autoLogout.hint,
                action: nil,
                actionTitle: String(localized: "Open System Settings")
            ))
        }
        if let update {
            messages.append(WindowMessage(
                source: .update,
                kind: .info,
                title: String(localized: "Update available"),
                text: String(localized: "LidAwake \(update.latest) is available. You have \(update.current)."),
                hint: nil,
                action: nil,
                actionTitle: String(localized: "Download")
            ))
        }
        return messages
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
