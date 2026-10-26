import Foundation
import LidAwakeShared
import UserNotifications

@MainActor
public protocol StopNotifying: AnyObject {
    func requestAuthorization()
    func post(title: String, body: String)
}

public enum StopNotice {
    public static let title = String(localized: "LidAwake turned off")

    public static func body(for record: StopRecord) -> String {
        switch record.reason {
        case .timer:
            return String(localized: "The timer ran out.")
        case .battery:
            guard let percent = record.batteryPercent else {
                return String(localized: "The battery dropped below the limit.")
            }
            return String(localized: "The battery dropped to \(percent)%.")
        case .batteryUnreadable:
            return String(localized: "The battery level could not be read.")
        case .thermal:
            return String(localized: "The Mac got too hot.")
        case .thermalUnreadable:
            return String(localized: "The thermal state could not be read.")
        case .powerUnreadable:
            return String(localized: "The power source could not be read.")
        case .leaseExpired:
            return String(localized: "LidAwake closed unexpectedly, so normal sleep was restored.")
        case .idle:
            guard let minutes = record.idleMinutes else {
                return String(localized: "Nothing was working for a while.")
            }
            return String(localized: "Nothing was working for \(minutes) minutes.")
        }
    }
}

/// The text shown when Run with Lid Closed could not be turned on.
public enum RefusalNotice {
    /// The helper words a refusal in English. The result code names the protection; the helper's text,
    /// fixed for the build the app runs with, tells its cases apart. Any other text is shown as it is.
    public static func text(for error: Error) -> String {
        guard case HelperError.helper(let code, let message) = error else { return error.localizedDescription }
        switch code {
        case .thermalLimitReached:
            if message == "The thermal state could not be read." {
                return String(localized: "The thermal state could not be read.")
            }
            if message.hasPrefix("The Mac is too hot") {
                return String(localized: "The Mac got too hot.")
            }
        case .batteryLimitReached:
            if message == "The battery level could not be read." {
                return String(localized: "The battery level could not be read.")
            }
            if message == "The power source could not be read." {
                return String(localized: "The power source could not be read.")
            }
            if let (percent, limit) = batteryLimit(in: message) {
                return String(localized: "The battery is at \(percent)%, at or below the \(limit)% limit.")
            }
        case .powerUnreadable:
            if message == "The power source could not be read." {
                return String(localized: "The power source could not be read.")
            }
        default:
            break
        }
        return message
    }

    private static func batteryLimit(in message: String) -> (Int, Int)? {
        let pattern = try! NSRegularExpression(pattern: "^The battery is at (\\d+)%, at or below the (\\d+)% limit\\.$")
        guard let match = pattern.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let percent = Range(match.range(at: 1), in: message).flatMap({ Int(message[$0]) }),
              let limit = Range(match.range(at: 2), in: message).flatMap({ Int(message[$0]) }) else { return nil }
        return (percent, limit)
    }
}

public enum PauseNotice {
    public static let title = String(localized: "LidAwake paused")
    public static let body = String(localized: "Running on battery. It resumes when you plug in.")
}

public enum ScreenLockNotice {
    public static let unavailable = String(localized: "Screen lock is not available on this macOS version.")
}

@MainActor
public final class UserNotificationNotifier: NSObject, StopNotifying, UNUserNotificationCenterDelegate {
    override public init() {
        super.init()
    }

    public func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // A menu bar app counts as frontmost while its window is open; show the banner anyway.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
