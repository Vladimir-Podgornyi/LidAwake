public enum HelperResultCode: Int, Equatable {
    case ok = 0
    case flagReadFailed = 1
    case flagWriteFailed = 2
    case markerFailed = 3
    case noSession = 4
    case invalidArgument = 5
    case batteryLimitReached = 6
    case stopReasonFailed = 7
}

public enum SleepFlagState: Int, Equatable {
    case unknown = -1
    case off = 0
    case on = 1

    public var token: String {
        switch self {
        case .unknown: return "unknown"
        case .off: return "0"
        case .on: return "1"
        }
    }
}

public enum SessionOwnership: Int, Equatable {
    case noSession = 0
    case ours = 1
    case foreign = 2

    public var token: String {
        switch self {
        case .noSession: return "none"
        case .ours: return "ours"
        case .foreign: return "foreign"
        }
    }
}

public struct HelperSessionStatus: Equatable {
    public let flag: SleepFlagState
    public let session: SessionOwnership
    /// Nil when the timer is off or no session is active.
    public let timerRemaining: Int?
    public let power: PowerReading

    public init(flag: SleepFlagState, session: SessionOwnership, timerRemaining: Int?, power: PowerReading) {
        self.flag = flag
        self.session = session
        self.timerRemaining = timerRemaining
        self.power = power
    }
}
