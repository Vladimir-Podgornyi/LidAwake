import Foundation
import LidAwakeShared

public struct SessionResult: Equatable {
    public let code: HelperResultCode
    public let message: String?

    public static let ok = SessionResult(code: .ok, message: nil)

    static func failure(_ code: HelperResultCode, _ error: Error) -> SessionResult {
        SessionResult(code: code, message: error.localizedDescription)
    }
}

public struct SessionStatus: Equatable {
    public let flag: SleepFlagState
    public let session: SessionOwnership
    /// Whole seconds, rounded up; nil when the timer is off or no session is active.
    public let timerRemaining: Int?
    public let power: PowerReading
    public let message: String?
}

/// Keeps SleepDisabled set while a leased session is active and ends it when a safety limit trips.
///
/// Not thread-safe: the helper calls it from one queue.
public final class LidSession {
    public enum Ownership: Equatable {
        case ours
        case foreign
    }

    private struct BatteryStop {
        let reason: StopReason
        let percent: Int?
        let message: String
    }

    private let flag: SleepFlag
    private let marker: OwnershipMarker
    private let clock: SessionClock
    private let power: PowerSourceReading
    private let stopReasons: StopReasonStore
    private let wallClock: () -> Date

    public private(set) var ownership: Ownership?
    public private(set) var deadline: TimeInterval?
    public private(set) var startedAt: TimeInterval?
    public private(set) var safety: SafetySettings = .off

    public var isActive: Bool { ownership != nil }

    public init(
        flag: SleepFlag,
        marker: OwnershipMarker,
        clock: SessionClock,
        power: PowerSourceReading,
        stopReasons: StopReasonStore,
        wallClock: @escaping () -> Date = Date.init
    ) {
        self.flag = flag
        self.marker = marker
        self.clock = clock
        self.power = power
        self.stopReasons = stopReasons
        self.wallClock = wallClock
    }

    public func start(lease: TimeInterval, safety: SafetySettings) -> SessionResult {
        guard safety.isValid else { return Self.invalidSafety }
        if isActive {
            return renew(lease: lease, safety: safety)
        }
        if let stop = batteryStop(limit: safety.batteryLimitPercent) {
            return SessionResult(code: .batteryLimitReached, message: stop.message)
        }

        let isSet: Bool
        do {
            isSet = try flag.read()
        } catch {
            return .failure(.flagReadFailed, error)
        }

        if isSet && !marker.isSet {
            begin(.foreign, lease: lease, safety: safety)
            return .ok
        }

        // The marker goes first: a crash after it leaves a flag that the next
        // cleanup clears, never a flag that looks foreign.
        do {
            try marker.set()
        } catch {
            return .failure(.markerFailed, error)
        }
        if !isSet {
            do {
                try flag.write(true)
            } catch {
                if (try? flag.write(false)) != nil {
                    try? marker.clear()
                }
                return .failure(.flagWriteFailed, error)
            }
        }
        begin(.ours, lease: lease, safety: safety)
        return .ok
    }

    public func renew(lease: TimeInterval, safety: SafetySettings) -> SessionResult {
        guard safety.isValid else { return Self.invalidSafety }
        guard isActive else {
            return SessionResult(code: .noSession, message: "No active session.")
        }
        deadline = clock.now + lease
        self.safety = safety
        guard ownership == .ours else { return .ok }

        let isSet: Bool
        do {
            isSet = try flag.read()
        } catch {
            return .failure(.flagReadFailed, error)
        }
        if !isSet {
            do {
                try flag.write(true)
            } catch {
                return .failure(.flagWriteFailed, error)
            }
        }
        return .ok
    }

    public func end() -> SessionResult {
        guard let ended = ownership else {
            return clearLeftover()
        }
        ownership = nil
        deadline = nil
        startedAt = nil
        safety = .off
        guard ended == .ours else { return .ok }
        return releaseFlag()
    }

    /// Ends the session when the timer, the battery limit or the lease runs out.
    @discardableResult
    public func enforceLimits() -> SessionResult? {
        guard isActive else { return nil }
        if let remaining = timerRemaining, remaining <= 0 {
            return stop(.timer, batteryPercent: nil)
        }
        if let battery = batteryStop(limit: safety.batteryLimitPercent) {
            return stop(battery.reason, batteryPercent: battery.percent)
        }
        if let deadline, clock.now >= deadline {
            return stop(.leaseExpired, batteryPercent: nil)
        }
        return nil
    }

    public func clearLeftover() -> SessionResult {
        guard !isActive, marker.isSet else { return .ok }
        return releaseFlag()
    }

    public func status() -> SessionStatus {
        let session: SessionOwnership
        switch ownership {
        case nil: session = .noSession
        case .ours: session = .ours
        case .foreign: session = .foreign
        }
        let remaining = timerRemaining.map { Int(max(0, $0).rounded(.up)) }
        let reading = power.read()
        do {
            return SessionStatus(
                flag: try flag.read() ? .on : .off,
                session: session,
                timerRemaining: remaining,
                power: reading,
                message: nil
            )
        } catch {
            return SessionStatus(
                flag: .unknown,
                session: session,
                timerRemaining: remaining,
                power: reading,
                message: error.localizedDescription
            )
        }
    }

    public func lastStopReason() -> StopRecord? {
        stopReasons.read()
    }

    public func clearStopReason() -> SessionResult {
        do {
            try stopReasons.clear()
        } catch {
            return .failure(.stopReasonFailed, error)
        }
        return .ok
    }

    private static let invalidSafety = SessionResult(
        code: .invalidArgument,
        message: "Timer must be 0 or \(SafetySettings.timerRange.lowerBound) to \(SafetySettings.timerRange.upperBound) seconds; battery limit must be 0 to 100 percent."
    )

    // Counted from the start of the session, even after the timer setting changes.
    private var timerRemaining: TimeInterval? {
        guard let startedAt, safety.timerSeconds > 0 else { return nil }
        return TimeInterval(safety.timerSeconds) - (clock.now - startedAt)
    }

    private func batteryStop(limit: Int) -> BatteryStop? {
        guard limit > 0 else { return nil }
        let reading = power.read()
        switch reading.battery {
        case .none:
            return nil
        case .unknown:
            return BatteryStop(reason: .batteryUnreadable, percent: nil, message: "The battery level could not be read.")
        case .percent(let percent):
            switch reading.source {
            case .ac:
                return nil
            case .unknown:
                return BatteryStop(reason: .batteryUnreadable, percent: nil, message: "The power source could not be read.")
            case .battery:
                guard percent <= limit else { return nil }
                return BatteryStop(
                    reason: .battery,
                    percent: percent,
                    message: "The battery is at \(percent)%, at or below the \(limit)% limit."
                )
            }
        }
    }

    private func stop(_ reason: StopReason, batteryPercent: Int?) -> SessionResult {
        // The session ends even when the reason cannot be saved.
        try? stopReasons.write(StopRecord(reason: reason, time: wallClock(), batteryPercent: batteryPercent))
        return end()
    }

    private func begin(_ ownership: Ownership, lease: TimeInterval, safety: SafetySettings) {
        self.ownership = ownership
        self.safety = safety
        startedAt = clock.now
        deadline = clock.now + lease
    }

    // The marker stays when the flag cannot be cleared, so a later cleanup retries.
    private func releaseFlag() -> SessionResult {
        do {
            try flag.write(false)
        } catch {
            return .failure(.flagWriteFailed, error)
        }
        do {
            try marker.clear()
        } catch {
            return .failure(.markerFailed, error)
        }
        return .ok
    }
}
