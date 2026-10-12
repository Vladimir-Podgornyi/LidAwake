import Foundation
import LidAwakeShared

public struct PowerEvent: Equatable {
    public let time: Date
    /// The name the scheduling process gave the event.
    public let owner: String
    public let type: String

    public init(time: Date, owner: String, type: String) {
        self.time = time
        self.owner = owner
        self.type = type
    }
}

public protocol PowerEventScheduling {
    /// Every scheduled power event in the system, whoever scheduled it.
    func events() throws -> [PowerEvent]
    /// Schedules a one-time wake under the helper's name.
    func scheduleWake(at time: Date) throws
    func cancelWake(at time: Date) throws
}

public enum WakeScheduleError: Error, Equatable, LocalizedError {
    case unreadable
    case scheduleFailed(Date, Int32)
    case cancelFailed(Date, Int32)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Could not read the scheduled power events."
        case .scheduleFailed(let time, let code):
            return "Could not schedule a wake at \(Self.format(time)): \(Self.format(code))."
        case .cancelFailed(let time, let code):
            return "Could not cancel the wake at \(Self.format(time)): \(Self.format(code))."
        }
    }

    private static func format(_ time: Date) -> String {
        ISO8601DateFormatter().string(from: time)
    }

    private static func format(_ code: Int32) -> String {
        "IOReturn \(String(format: "0x%08X", UInt32(bitPattern: code))) (\(code))"
    }
}

public struct WakePlan: Equatable {
    public let cancel: [Date]
    public let add: [Date]
}

public enum WakeSchedule {
    public static let owner = HelperConstants.helperIdentifier
    /// The value of `kIOPMAutoWake`.
    public static let wakeType = "wake"
    /// Two wakes stay scheduled, so the next one still fires if the app misses rescheduling after a wake.
    public static let count = 2
    /// A wake closer than this to now is skipped in favour of the next day's.
    public static let lead: TimeInterval = 60

    public static func isOurs(_ event: PowerEvent) -> Bool {
        event.owner == owner && event.type == wakeType
    }

    /// The next `count` times at `minuteOfDay` on the local clock of `calendar.timeZone`, later than `lead` from now.
    /// A time skipped by a clock change moves to the first minute after the change;
    /// a time that occurs twice is taken the first time.
    public static func wakes(minuteOfDay: Int, after now: Date, calendar: Calendar) -> [Date] {
        let zone = calendar.timeZone
        var wallCalendar = calendar
        wallCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let earliest = now.addingTimeInterval(lead)
        // Local clock readings are handled as if they were GMT, so day arithmetic sees no clock changes.
        let wallNow = now.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: now)))
        let today = wallCalendar.startOfDay(for: wallNow)
        var wakes: [Date] = []
        for day in 0..<(count + 2) where wakes.count < count {
            guard let midnight = wallCalendar.date(byAdding: .day, value: day, to: today) else { continue }
            let time = instant(ofWallTime: midnight.addingTimeInterval(TimeInterval(minuteOfDay * 60)), in: zone)
            if time > earliest {
                wakes.append(time)
            }
        }
        return wakes
    }

    /// Our wakes not wanted are cancelled and wanted times not yet ours are added; other events are left alone.
    public static func plan(wanted: [Date], events: [PowerEvent]) -> WakePlan {
        let ours = events.filter(isOurs).map(\.time)
        let wantedSeconds = Set(wanted.map(seconds))
        let ourSeconds = Set(ours.map(seconds))
        return WakePlan(
            cancel: ours.filter { !wantedSeconds.contains(seconds($0)) }.sorted(),
            add: wanted.filter { !ourSeconds.contains(seconds($0)) }.sorted()
        )
    }

    private static func seconds(_ time: Date) -> Int64 {
        Int64(time.timeIntervalSince1970.rounded())
    }

    private static func instant(ofWallTime wall: Date, in zone: TimeZone) -> Date {
        let offsets = Set([-86_400.0, 0, 86_400].map { zone.secondsFromGMT(for: wall.addingTimeInterval($0)) })
        let valid = offsets.compactMap { offset -> Date? in
            let time = wall.addingTimeInterval(-TimeInterval(offset))
            return zone.secondsFromGMT(for: time) == offset ? time : nil
        }
        if let first = valid.min() {
            return first
        }
        // The clocks jump over this reading; the first minute that exists comes right at the change.
        let beforeChange = wall.addingTimeInterval(-TimeInterval(offsets.max()!))
        return zone.nextDaylightSavingTimeTransition(after: beforeChange)
            ?? wall.addingTimeInterval(-TimeInterval(offsets.min()!))
    }
}

/// Keeps the helper's own wakes at the requested time of day and leaves every other power event alone.
/// The system keeps the events, so they fire even when the helper is not running.
///
/// Not thread-safe: the helper calls it from one queue.
public final class WakeScheduler {
    private let events: PowerEventScheduling
    private let now: () -> Date
    private let calendar: () -> Calendar

    public init(events: PowerEventScheduling, now: @escaping () -> Date, calendar: @escaping () -> Calendar) {
        self.events = events
        self.now = now
        self.calendar = calendar
    }

    /// `minuteOfDay` from 0 to 1439 keeps the next `WakeSchedule.count` wakes at that time; -1 cancels ours.
    public func set(minuteOfDay: Int) -> SessionResult {
        guard minuteOfDay == ScheduledWake.off || ScheduledWake.minutes.contains(minuteOfDay) else {
            return SessionResult(code: .invalidArgument, message: "Minute of day must be 0 to 1439, or -1 to cancel.")
        }
        let current: [PowerEvent]
        do {
            current = try events.events()
        } catch {
            return .failure(.wakeScheduleFailed, error)
        }
        let wanted = minuteOfDay == ScheduledWake.off
            ? []
            : WakeSchedule.wakes(minuteOfDay: minuteOfDay, after: now(), calendar: calendar())
        let plan = WakeSchedule.plan(wanted: wanted, events: current)
        var firstError: Error?
        // Added before the old ones are cancelled, and nothing is rolled back,
        // so a failure leaves a wake too many rather than none.
        for time in plan.add {
            do { try events.scheduleWake(at: time) } catch { firstError = firstError ?? error }
        }
        for time in plan.cancel {
            do { try events.cancelWake(at: time) } catch { firstError = firstError ?? error }
        }
        if let firstError {
            return .failure(.wakeScheduleFailed, firstError)
        }
        return .ok
    }

    public func scheduledWakes() throws -> [Date] {
        try events.events().filter(WakeSchedule.isOurs).map(\.time).sorted()
    }
}
