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
    public let thermal: ThermalState
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

    private struct LimitStop {
        let reason: StopReason
        let percent: Int?
        let message: String
    }

    private let flag: SleepFlag
    private let marker: OwnershipMarker
    private let clock: SessionClock
    private let power: PowerSourceReading
    private let thermal: ThermalStateReading
    private let stopReasons: StopReasonStore
    private let wallClock: () -> Date

    public private(set) var ownership: Ownership?
    public private(set) var deadline: TimeInterval?
    public private(set) var startedAt: TimeInterval?
    public private(set) var safety: SafetySettings = .off
    private var lastLeftoverAttempt: TimeInterval?

    public static let leftoverRetryInterval: TimeInterval = 30

    public var isActive: Bool { ownership != nil }

    public init(
        flag: SleepFlag,
        marker: OwnershipMarker,
        clock: SessionClock,
        power: PowerSourceReading,
        thermal: ThermalStateReading,
        stopReasons: StopReasonStore,
        wallClock: @escaping () -> Date = Date.init
    ) {
        self.flag = flag
        self.marker = marker
        self.clock = clock
        self.power = power
        self.thermal = thermal
        self.stopReasons = stopReasons
        self.wallClock = wallClock
    }

    public func start(lease: TimeInterval, safety: SafetySettings) -> SessionResult {
        guard safety.isValid else { return Self.invalidSafety }
        if isActive {
            return renew(lease: lease, safety: safety)
        }
        if let stop = thermalStop(enabled: safety.thermalProtection) {
            return SessionResult(code: .thermalLimitReached, message: stop.message)
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

        let isSet: Bool
        do {
            isSet = try flag.read()
        } catch {
            return .failure(.flagReadFailed, error)
        }
        guard !isSet else { return .ok }
        if ownership == .foreign {
            return takeOver()
        }
        do {
            try flag.write(true)
        } catch {
            return .failure(.flagWriteFailed, error)
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

    /// Ends the session when the timer runs out, the Mac gets too hot, the battery reaches its limit
    /// or the lease runs out, checked in that order.
    @discardableResult
    public func enforceLimits() -> SessionResult? {
        guard isActive else { return nil }
        if let remaining = timerRemaining, remaining <= 0 {
            return stop(.timer, batteryPercent: nil)
        }
        if let thermal = thermalStop(enabled: safety.thermalProtection) {
            return stop(thermal.reason, batteryPercent: nil)
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

    /// True while the helper has to stay running: a session is active or a flag it set is still left over.
    public var needsHelper: Bool {
        isActive || marker.isSet
    }

    /// Clears a flag left by an earlier run, at most once per `leftoverRetryInterval`.
    /// Returns nil when there was nothing to do or the last attempt is too recent.
    @discardableResult
    public func retryLeftover() -> SessionResult? {
        guard !isActive, marker.isSet else { return nil }
        if let lastLeftoverAttempt, clock.now - lastLeftoverAttempt < Self.leftoverRetryInterval {
            return nil
        }
        lastLeftoverAttempt = clock.now
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
        let thermalState = thermal.read()
        do {
            return SessionStatus(
                flag: try flag.read() ? .on : .off,
                session: session,
                timerRemaining: remaining,
                power: reading,
                thermal: thermalState,
                message: nil
            )
        } catch {
            return SessionStatus(
                flag: .unknown,
                session: session,
                timerRemaining: remaining,
                power: reading,
                thermal: thermalState,
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

    private func thermalStop(enabled: Bool) -> LimitStop? {
        guard enabled else { return nil }
        let state = thermal.read()
        switch state {
        case .nominal, .fair:
            return nil
        case .serious, .critical:
            return LimitStop(reason: .thermal, percent: nil, message: "The Mac is too hot (thermal state \(state.token)).")
        case .unknown:
            return LimitStop(reason: .thermalUnreadable, percent: nil, message: "The thermal state could not be read.")
        }
    }

    private func batteryStop(limit: Int) -> LimitStop? {
        guard limit > 0 else { return nil }
        let reading = power.read()
        switch reading.battery {
        case .none:
            return nil
        case .unknown:
            return LimitStop(reason: .batteryUnreadable, percent: nil, message: "The battery level could not be read.")
        case .percent(let percent):
            switch reading.source {
            case .ac:
                return nil
            case .unknown:
                return LimitStop(reason: .batteryUnreadable, percent: nil, message: "The power source could not be read.")
            case .battery:
                guard percent <= limit else { return nil }
                return LimitStop(
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

    // Same order as start: the marker before the flag.
    private func takeOver() -> SessionResult {
        do {
            try marker.set()
        } catch {
            return .failure(.markerFailed, error)
        }
        do {
            try flag.write(true)
        } catch {
            if (try? flag.write(false)) != nil {
                try? marker.clear()
            }
            return .failure(.flagWriteFailed, error)
        }
        ownership = .ours
        return .ok
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
