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

/// What a minute of the idle count came down to, in the order the count rules check it.
public enum IdleCause: Equatable {
    /// A program asked the system to stay awake; the smallest of the names seen in the minute.
    case app(String)
    case input
    /// The load cleared the count. `busiest` is the process that spent the most processor time in
    /// the minute, as the system names it; nil when the processes could not be read.
    case load(busiest: String?)
    /// The first quiet minute; `minutes` is the number the count runs to.
    case idle(minutes: Int)
}

/// A change in what keeps the idle count from running, at the end of the minute it was decided on.
public struct IdleEvent: Equatable {
    public let time: Date
    public let cause: IdleCause

    public init(time: Date, cause: IdleCause) {
        self.time = time
        self.cause = cause
    }
}

/// How events cross from the helper to the app: one per line, fields separated by tabs.
public enum IdleEventWire {
    private static let app = "app"
    private static let input = "input"
    private static let load = "load"
    private static let idle = "idle"

    public static func encode(_ events: [IdleEvent]) -> String {
        events.map { event in
            var fields = [String(event.time.timeIntervalSince1970)]
            switch event.cause {
            case .app(let name):
                fields += [app, field(name)]
            case .input:
                fields += [input]
            case .load(let busiest):
                fields += [load] + (busiest.map { [field($0)] } ?? [])
            case .idle(let minutes):
                fields += [idle, String(minutes)]
            }
            return fields.joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    /// Lines it cannot make sense of, such as kinds added by a later helper, are skipped.
    public static func decode(_ text: String) -> [IdleEvent] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, let seconds = Double(fields[0]) else { return nil }
            let cause: IdleCause
            switch (fields[1], fields.count) {
            case (app, 3):
                cause = .app(fields[2])
            case (input, 2):
                cause = .input
            case (load, 2):
                cause = .load(busiest: nil)
            case (load, 3):
                cause = .load(busiest: fields[2])
            case (idle, 3):
                guard let minutes = Int(fields[2]) else { return nil }
                cause = .idle(minutes: minutes)
            default:
                return nil
            }
            return IdleEvent(time: Date(timeIntervalSince1970: seconds), cause: cause)
        }
    }

    // Process names may hold any character; the two separators become spaces.
    private static func field(_ name: String) -> String {
        name.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
