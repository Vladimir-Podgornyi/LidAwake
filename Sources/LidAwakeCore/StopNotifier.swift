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
        }
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
