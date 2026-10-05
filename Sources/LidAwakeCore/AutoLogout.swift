import Combine
import CoreFoundation
import Foundation

/// The macOS setting that logs the user out after a period of inactivity. LidAwake only reads it.
public protocol AutoLogoutSource {
    /// Seconds of inactivity before macOS logs out; nil when the setting is off.
    func delaySeconds() -> Int?
}

/// Reads `com.apple.autologout.AutoLogOutDelay` from the global preferences, the way System
/// Settings writes it to /Library/Preferences/.GlobalPreferences.plist.
public struct SystemAutoLogoutSource: AutoLogoutSource {
    public static let key = "com.apple.autologout.AutoLogOutDelay"

    private let read: (String) -> Any?

    public init() {
        read = { key in
            // Drops values cached in this process, so a change in System Settings shows up
            // the next time the window opens.
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
            return CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication)
        }
    }

    init(read: @escaping (String) -> Any?) {
        self.read = read
    }

    public func delaySeconds() -> Int? {
        let seconds: Int?
        switch read(Self.key) {
        case let number as NSNumber:
            seconds = number.intValue
        case let text as String:
            seconds = Int(text.trimmingCharacters(in: .whitespaces))
        default:
            seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        return seconds
    }
}

public enum AutoLogoutLinks {
    /// System Settings > Privacy & Security, where the Advanced button holds the setting.
    public static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
    /// The same section at its Advanced anchor, as listed in the section's search terms
    /// (PrivacySecurity.searchTerms in SecurityPrivacyExtension.appex).
    public static let advancedSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Advanced")!
}

/// The warning that the mode ends when macOS logs the user out.
public struct AutoLogoutNotice: Equatable {
    public let delaySeconds: Int

    /// nil in Off, with the setting off, when the timer ends the mode no later than the logout,
    /// or when the warning was dismissed at a delay no longer than the current one.
    public init?(mode: Mode, delaySeconds: Int?, timerSeconds: Int?, dismissedDelay: Int? = nil) {
        guard mode != .off, let delaySeconds else { return nil }
        if let timerSeconds, timerSeconds <= delaySeconds { return nil }
        if let dismissedDelay, delaySeconds >= dismissedDelay { return nil }
        self.delaySeconds = delaySeconds
    }

    public var title: String {
        String(localized: "macOS will log you out")
    }

    /// The way to the switch, in the labels System Settings itself uses.
    public var hint: String {
        String(localized: "Privacy & Security > Advanced… > Log out automatically after inactivity")
    }

    public var text: String {
        String(
            localized: "Automatic logout after \(DurationFormat.remaining(delaySeconds)) of inactivity is on. The mode ends when macOS logs you out."
        )
    }
}

/// The `--auto-logout-status` line.
public enum AutoLogoutReport {
    public static func line(delaySeconds: Int?) -> String {
        "auto-logout=\(delaySeconds.map(String.init) ?? "off")"
    }
}

/// Keeps the last read value of the setting for the window, and the delay at which the user
/// dismissed the warning.
@MainActor
public final class AutoLogoutMonitor: ObservableObject {
    public static let dismissedDelayKey = "autoLogoutDismissedDelay"

    @Published public private(set) var delaySeconds: Int?
    @Published public private(set) var dismissedDelay: Int?

    private let source: AutoLogoutSource
    private let defaults: UserDefaults

    public init(source: AutoLogoutSource = SystemAutoLogoutSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        delaySeconds = source.delaySeconds()
        dismissedDelay = (defaults.object(forKey: Self.dismissedDelayKey) as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Hides the warning until the delay gets shorter than it is now.
    public func dismiss() {
        guard let delaySeconds else { return }
        defaults.set(delaySeconds, forKey: Self.dismissedDelayKey)
        dismissedDelay = delaySeconds
    }

    public func refresh() {
        let value = source.delaySeconds()
        if value != delaySeconds {
            delaySeconds = value
        }
    }

    public func notice(mode: Mode, timerSeconds: Int?) -> AutoLogoutNotice? {
        AutoLogoutNotice(mode: mode, delaySeconds: delaySeconds, timerSeconds: timerSeconds, dismissedDelay: dismissedDelay)
    }
}
