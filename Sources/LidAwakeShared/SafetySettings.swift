import Foundation

public struct SafetySettings: Equatable {
    public static let timerRange = 60...86_400
    public static let batteryLimitRange = 1...100
    public static let idleSleepRange = 1...240
    public static let off = SafetySettings(timerSeconds: 0, batteryLimitPercent: 0, thermalProtection: false)

    /// 0 turns the timer off.
    public let timerSeconds: Int
    /// 0 turns the battery limit off.
    public let batteryLimitPercent: Int
    /// Ends the session when the Mac gets too hot.
    public let thermalProtection: Bool
    /// Pauses the session while the Mac runs on battery.
    public let chargingOnly: Bool
    /// Minutes of an idle Mac that end the session; 0 turns it off.
    public let idleSleepMinutes: Int
    /// Apps whose started programs count as work for the idle count; empty turns this off.
    public let watchedAppPaths: [String]

    public init(
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        chargingOnly: Bool = false,
        idleSleepMinutes: Int = 0,
        watchedAppPaths: [String] = []
    ) {
        self.timerSeconds = timerSeconds
        self.batteryLimitPercent = batteryLimitPercent
        self.thermalProtection = thermalProtection
        self.chargingOnly = chargingOnly
        self.idleSleepMinutes = idleSleepMinutes
        self.watchedAppPaths = watchedAppPaths
    }

    public var isValid: Bool {
        (timerSeconds == 0 || Self.timerRange.contains(timerSeconds))
            && (batteryLimitPercent == 0 || Self.batteryLimitRange.contains(batteryLimitPercent))
            && (idleSleepMinutes == 0 || Self.idleSleepRange.contains(idleSleepMinutes))
            && WatchedApps.isValid(watchedAppPaths)
    }
}

public enum StopReason: String, Codable, Equatable {
    case timer
    case battery
    case batteryUnreadable
    case thermal
    case thermalUnreadable
    case powerUnreadable
    case leaseExpired
    case idle
}

public struct StopRecord: Codable, Equatable {
    public let reason: StopReason
    public let time: Date
    /// Set for `battery`: the level that triggered the stop.
    public let batteryPercent: Int?
    /// Set for `idle`: the minutes nothing was working.
    public let idleMinutes: Int?

    public init(reason: StopReason, time: Date, batteryPercent: Int? = nil, idleMinutes: Int? = nil) {
        self.reason = reason
        self.time = time
        self.batteryPercent = batteryPercent
        self.idleMinutes = idleMinutes
    }
}
