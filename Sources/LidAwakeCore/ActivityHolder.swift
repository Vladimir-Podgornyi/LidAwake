import Foundation

public protocol ActivityHolding: AnyObject {
    func begin()
    func end()
}

/// Keeps App Nap from delaying lease renewals; idle system sleep stays allowed.
public final class AppNapActivity: ActivityHolding {
    private var token: NSObjectProtocol?

    public init() {}

    public func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Renewing the Run with Lid Closed session"
        )
    }

    public func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}
