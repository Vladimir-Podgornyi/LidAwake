import Foundation

/// What the helper sees right now: either a reason the Mac counts as busy, or the idle count.
public enum IdleState: Int, Equatable {
    /// The setting is off, no session is running, or the session is paused.
    case off = 0
    case busyCPU = 1
    case busyApp = 2
    case busyInput = 3
    case counting = 4

    public var token: String {
        switch self {
        case .off: return "off"
        case .busyCPU: return "busy-cpu"
        case .busyApp: return "busy-app"
        case .busyInput: return "busy-input"
        case .counting: return "counting"
        }
    }
}

/// The readings behind the idle count, as the helper takes them.
public struct IdleStatus: Equatable {
    public let state: IdleState
    public let countedMinutes: Int
    /// 0 while the count is off.
    public let requiredMinutes: Int
    /// Cores busy over the last minute, or over a shorter span right after the helper starts;
    /// nil when the counter could not be read.
    public let cores: Double?
    /// Seconds since the last keyboard or mouse input; nil when it could not be read.
    public let inputIdleSeconds: Double?
    /// Names of the processes whose sleep requests count; nil when the requests could not be read.
    public let holders: [String]?

    public init(
        state: IdleState,
        countedMinutes: Int,
        requiredMinutes: Int,
        cores: Double?,
        inputIdleSeconds: Double?,
        holders: [String]?
    ) {
        self.state = state
        self.countedMinutes = countedMinutes
        self.requiredMinutes = requiredMinutes
        self.cores = cores
        self.inputIdleSeconds = inputIdleSeconds
        self.holders = holders
    }

    public var token: String {
        switch state {
        case .counting: return "\(state.token):\(countedMinutes)/\(requiredMinutes)"
        default: return state.token
        }
    }

    public var coresToken: String {
        guard let cores else { return "unreadable" }
        return String(format: "%.2f", cores)
    }

    public var inputToken: String {
        guard let inputIdleSeconds else { return "unreadable" }
        return String(format: "%.1f", inputIdleSeconds)
    }

    /// Quoted, because process names may contain spaces and commas.
    public var holdersToken: String {
        guard let holders else { return "unreadable" }
        return holders.isEmpty ? "none" : "\"\(holders.joined(separator: ","))\""
    }
}
