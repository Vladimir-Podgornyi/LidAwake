import Foundation
import LidAwakeShared
import UserNotifications

@MainActor
public protocol StopNotifying: AnyObject {
    func requestAuthorization()
    func post(title: String, body: String)
}

public enum StopNotice {
    public static let title = "LidAwake turned off"

    public static func body(for record: StopRecord) -> String {
        switch record.reason {
        case .timer:
            return "The timer ran out."
        case .battery:
            guard let percent = record.batteryPercent else {
                return "The battery dropped below the limit."
            }
            return "The battery dropped to \(percent)%."
        case .batteryUnreadable:
            return "The battery level could not be read."
        case .leaseExpired:
            return "LidAwake closed unexpectedly, so normal sleep was restored."
        }
    }
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
        completionHandler([.banner, .sound])
    }
}
