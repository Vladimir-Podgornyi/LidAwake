import Foundation

public struct SafetySettings: Equatable {
    public static let timerRange = 60...86_400
    public static let batteryLimitRange = 1...100
    public static let off = SafetySettings(timerSeconds: 0, batteryLimitPercent: 0)

    /// 0 turns the timer off.
    public let timerSeconds: Int
    /// 0 turns the battery limit off.
    public let batteryLimitPercent: Int

    public init(timerSeconds: Int, batteryLimitPercent: Int) {
        self.timerSeconds = timerSeconds
        self.batteryLimitPercent = batteryLimitPercent
    }

    public var isValid: Bool {
        (timerSeconds == 0 || Self.timerRange.contains(timerSeconds))
            && (batteryLimitPercent == 0 || Self.batteryLimitRange.contains(batteryLimitPercent))
    }
}

public enum StopReason: String, Codable, Equatable {
    case timer
    case battery
    case batteryUnreadable
    case leaseExpired
}

public struct StopRecord: Codable, Equatable {
    public let reason: StopReason
    public let time: Date
    /// Set for `battery`: the level that triggered the stop.
    public let batteryPercent: Int?

    public init(reason: StopReason, time: Date, batteryPercent: Int? = nil) {
        self.reason = reason
        self.time = time
        self.batteryPercent = batteryPercent
    }
}
