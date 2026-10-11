import Foundation
import LidAwakeShared

/// What happened, without any text: the log window words it in the language of the interface.
public enum ActivityEvent: Equatable {
    case modeOn(Mode)
    case modeOff(Mode, ModeOffReason)
    case paused
    case resumed
    case sleep
    case wake
    /// A program asked macOS not to sleep.
    case keptAwakeByApp(String)
    /// `busiest` is the process that spent the most processor time in that minute.
    case keptAwakeByLoad(busiest: String?)
    case keptAwakeByInput
    /// Nothing worked and the idle count began; `minutes` is the number it runs to.
    case idleStarted(minutes: Int)
}

extension ActivityEvent {
    public init(_ cause: IdleCause) {
        switch cause {
        case .app(let name): self = .keptAwakeByApp(name)
        case .input: self = .keptAwakeByInput
        case .load(let busiest): self = .keptAwakeByLoad(busiest: busiest)
        case .idle(let minutes): self = .idleStarted(minutes: minutes)
        }
    }
}

public enum ModeOffReason: Equatable {
    case user
    /// Set by the helper, or by the app for the Keep Screen On timer. `timerSeconds` is the length
    /// of the timer when it fired.
    case stopped(StopReason, batteryPercent: Int? = nil, idleMinutes: Int? = nil, timerSeconds: Int? = nil)
    case error(String)
    /// A session of an earlier run, ended when the app started.
    case previousSession
}

public struct ActivityEntry: Equatable {
    public let time: Date
    public let event: ActivityEvent

    public init(time: Date, event: ActivityEvent) {
        self.time = time
        self.event = event
    }
}

@MainActor
public protocol ActivityLogging: AnyObject {
    /// `time` is when the event happened; nil means now.
    func record(_ event: ActivityEvent, at time: Date?)
}

extension ActivityLogging {
    public func record(_ event: ActivityEvent) {
        record(event, at: nil)
    }
}

/// Keeps the newest events in a file on this Mac, ordered by when they happened.
@MainActor
public final class ActivityLog: ActivityLogging {
    public static let capacity = 200

    public nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.vladimirpodgornyi.LidAwake", isDirectory: true)
            .appendingPathComponent("activity-log.json")
    }

    public let fileURL: URL
    private let now: () -> Date
    private var loaded: [ActivityEntry]?

    public init(fileURL: URL = ActivityLog.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    /// Oldest first.
    public var entries: [ActivityEntry] {
        if let loaded {
            return loaded
        }
        let read = Self.read(from: fileURL)
        loaded = read
        return read
    }

    public func record(_ event: ActivityEvent, at time: Date?) {
        let entry = ActivityEntry(time: time ?? now(), event: event)
        var list = entries
        // A reason the helper still reports after an earlier report could not clear it.
        guard !list.contains(entry) else { return }
        // Events reported late, such as a stop found after the Mac woke, go where they happened.
        let index = list.lastIndex { $0.time <= entry.time }.map { $0 + 1 } ?? 0
        list.insert(entry, at: index)
        if list.count > Self.capacity {
            list.removeFirst(list.count - Self.capacity)
        }
        loaded = list
        save(list)
    }

    public func clear() {
        loaded = []
        save([])
    }

    /// An unreadable file counts as an empty log.
    public nonisolated static func read(from url: URL) -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ActivityLogFile.self, from: data),
              file.version == ActivityLogFile.currentVersion
        else {
            return []
        }
        return file.entries.compactMap(\.entry).sorted { $0.time < $1.time }
    }

    // The log only informs, so a failed write is dropped rather than shown.
    private func save(_ list: [ActivityEntry]) {
        let file = ActivityLogFile(version: ActivityLogFile.currentVersion, entries: list.map(StoredEntry.init))
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? Self.write(data, to: fileURL)
    }

    /// Writes a private temporary file next to the log and renames it over the log, so a reader
    /// sees either the old or the new file, never a part of one.
    private static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, url.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// The file format. `version` changes only when old readers could not make sense of the file;
/// new kinds of events keep it, because readers skip kinds they do not know.
struct ActivityLogFile: Codable {
    static let currentVersion = 1

    let version: Int
    let entries: [StoredEntry]
}

struct StoredEntry: Codable {
    /// Nil for an entry of a kind this version does not know.
    let entry: ActivityEntry?

    init(_ entry: ActivityEntry) {
        self.entry = entry
    }

    private enum Key: String, CodingKey {
        case kind, time, mode, reason, battery, idle, timer, message, name, busiest, minutes
    }

    // A damaged entry is skipped like an unknown one, so it does not cost the rest of the log.
    init(from decoder: Decoder) {
        entry = (try? Self.entry(from: decoder)) ?? nil
    }

    private static func entry(from decoder: Decoder) throws -> ActivityEntry? {
        let container = try decoder.container(keyedBy: Key.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let event: ActivityEvent?
        switch kind {
        case ActivityToken.modeOn:
            event = try container.decode(String.self, forKey: .mode).modeFromToken.map { .modeOn($0) }
        case ActivityToken.modeOff:
            event = try modeOff(from: container)
        case ActivityToken.paused:
            event = .paused
        case ActivityToken.resumed:
            event = .resumed
        case ActivityToken.sleep:
            event = .sleep
        case ActivityToken.wake:
            event = .wake
        case ActivityToken.busyApp:
            event = .keptAwakeByApp(try container.decode(String.self, forKey: .name))
        case ActivityToken.busyCPU:
            event = .keptAwakeByLoad(busiest: try container.decodeIfPresent(String.self, forKey: .busiest))
        case ActivityToken.busyInput:
            event = .keptAwakeByInput
        case ActivityToken.idleStart:
            event = .idleStarted(minutes: try container.decode(Int.self, forKey: .minutes))
        default:
            event = nil
        }
        guard let event else { return nil }
        let time = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .time))
        return ActivityEntry(time: time, event: event)
    }

    private static func modeOff(from container: KeyedDecodingContainer<Key>) throws -> ActivityEvent? {
        guard let mode = try container.decode(String.self, forKey: .mode).modeFromToken else { return nil }
        let token = try container.decode(String.self, forKey: .reason)
        let reason: ModeOffReason
        switch token {
        case ActivityToken.user:
            reason = .user
        case ActivityToken.error:
            reason = .error(try container.decodeIfPresent(String.self, forKey: .message) ?? "")
        case ActivityToken.previousSession:
            reason = .previousSession
        default:
            guard let stop = ActivityToken.stopReason(token) else { return nil }
            reason = .stopped(
                stop,
                batteryPercent: try container.decodeIfPresent(Int.self, forKey: .battery),
                idleMinutes: try container.decodeIfPresent(Int.self, forKey: .idle),
                timerSeconds: try container.decodeIfPresent(Int.self, forKey: .timer)
            )
        }
        return .modeOff(mode, reason)
    }

    func encode(to encoder: Encoder) throws {
        guard let entry else { return }
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(ActivityToken.kind(of: entry.event), forKey: .kind)
        try container.encode(entry.time.timeIntervalSince1970, forKey: .time)
        switch entry.event {
        case .modeOn(let mode):
            try container.encode(ActivityToken.mode(mode), forKey: .mode)
        case .modeOff(let mode, let reason):
            try container.encode(ActivityToken.mode(mode), forKey: .mode)
            try container.encode(ActivityToken.reason(reason), forKey: .reason)
            switch reason {
            case .user, .previousSession:
                break
            case .error(let message):
                try container.encode(message, forKey: .message)
            case .stopped(_, let battery, let idle, let timer):
                try container.encodeIfPresent(battery, forKey: .battery)
                try container.encodeIfPresent(idle, forKey: .idle)
                try container.encodeIfPresent(timer, forKey: .timer)
            }
        case .keptAwakeByApp(let name):
            try container.encode(name, forKey: .name)
        case .keptAwakeByLoad(let busiest):
            try container.encodeIfPresent(busiest, forKey: .busiest)
        case .idleStarted(let minutes):
            try container.encode(minutes, forKey: .minutes)
        case .paused, .resumed, .sleep, .wake, .keptAwakeByInput:
            break
        }
    }
}

/// The words used for events in the file and by `--print-log`.
public enum ActivityToken {
    static let modeOn = "mode-on"
    static let modeOff = "mode-off"
    static let paused = "paused"
    static let resumed = "resumed"
    static let sleep = "sleep"
    static let wake = "wake"
    static let busyApp = "busy-app"
    static let busyCPU = "busy-cpu"
    static let busyInput = "busy-input"
    static let idleStart = "idle-start"
    static let user = "user"
    static let error = "error"
    static let previousSession = "previous-session"

    private static let stopReasons: [(StopReason, String)] = [
        (.timer, "timer"),
        (.battery, "battery"),
        (.batteryUnreadable, "battery-unreadable"),
        (.thermal, "thermal"),
        (.thermalUnreadable, "thermal-unreadable"),
        (.powerUnreadable, "power-unreadable"),
        (.leaseExpired, "lease-expired"),
        (.idle, "idle"),
    ]

    static func kind(of event: ActivityEvent) -> String {
        switch event {
        case .modeOn: return modeOn
        case .modeOff: return modeOff
        case .paused: return paused
        case .resumed: return resumed
        case .sleep: return sleep
        case .wake: return wake
        case .keptAwakeByApp: return busyApp
        case .keptAwakeByLoad: return busyCPU
        case .keptAwakeByInput: return busyInput
        case .idleStarted: return idleStart
        }
    }

    static func mode(_ mode: Mode) -> String {
        switch mode {
        case .off: return "off"
        case .keepScreenOn: return "keep-screen-on"
        case .lidClosed: return "lid-closed"
        }
    }

    static func reason(_ reason: ModeOffReason) -> String {
        switch reason {
        case .user: return user
        case .error: return error
        case .previousSession: return previousSession
        case .stopped(let stop, _, _, _): return stopReason(stop)
        }
    }

    static func stopReason(_ reason: StopReason) -> String {
        stopReasons.first { $0.0 == reason }!.1
    }

    static func stopReason(_ token: String) -> StopReason? {
        stopReasons.first { $0.1 == token }?.0
    }

    /// One line for `--print-log`: the time with its offset from UTC, then the event as words.
    public static func line(for entry: ActivityEntry, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        var parts = [formatter.string(from: entry.time), kind(of: entry.event)]
        switch entry.event {
        case .modeOn(let mode):
            parts.append("mode=\(self.mode(mode))")
        case .modeOff(let mode, let reason):
            parts.append("mode=\(self.mode(mode))")
            parts.append("reason=\(self.reason(reason))")
            switch reason {
            case .user, .previousSession:
                break
            case .error(let message):
                parts.append("message=\(quoted(message))")
            case .stopped(_, let battery, let idle, let timer):
                if let battery { parts.append("battery=\(battery)") }
                if let idle { parts.append("idle=\(idle)") }
                if let timer { parts.append("timer=\(timer)") }
            }
        case .keptAwakeByApp(let name):
            parts.append("name=\(quoted(name))")
        case .keptAwakeByLoad(let busiest):
            if let busiest { parts.append("busiest=\(quoted(busiest))") }
        case .idleStarted(let minutes):
            parts.append("minutes=\(minutes)")
        case .paused, .resumed, .sleep, .wake, .keptAwakeByInput:
            break
        }
        return parts.joined(separator: " ")
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

private extension String {
    var modeFromToken: Mode? {
        Mode.allCases.first { $0 != .off && ActivityToken.mode($0) == self }
    }
}

/// Records nothing, so a controller made for the window snapshots leaves the log file alone.
@MainActor
public final class NoActivityLog: ActivityLogging {
    public nonisolated init() {}

    public func record(_ event: ActivityEvent, at time: Date?) {}
}
