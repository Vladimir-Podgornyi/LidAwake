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
    public let message: String?
}

/// Keeps SleepDisabled set while a leased session is active.
///
/// Not thread-safe: the helper calls it from one queue.
public final class LidSession {
    public enum Ownership: Equatable {
        case ours
        case foreign
    }

    private let flag: SleepFlag
    private let marker: OwnershipMarker
    private let clock: SessionClock

    public private(set) var ownership: Ownership?
    public private(set) var deadline: TimeInterval?

    public var isActive: Bool { ownership != nil }

    public init(flag: SleepFlag, marker: OwnershipMarker, clock: SessionClock) {
        self.flag = flag
        self.marker = marker
        self.clock = clock
    }

    public func start(lease: TimeInterval) -> SessionResult {
        if isActive {
            return renew(lease: lease)
        }

        let isSet: Bool
        do {
            isSet = try flag.read()
        } catch {
            return .failure(.flagReadFailed, error)
        }

        if isSet && !marker.isSet {
            begin(.foreign, lease: lease)
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
        begin(.ours, lease: lease)
        return .ok
    }

    public func renew(lease: TimeInterval) -> SessionResult {
        guard isActive else {
            return SessionResult(code: .noSession, message: "No active session.")
        }
        deadline = clock.now + lease
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
        guard ended == .ours else { return .ok }
        return releaseFlag()
    }

    @discardableResult
    public func expireIfNeeded() -> SessionResult? {
        guard let deadline, clock.now >= deadline else { return nil }
        return end()
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
        do {
            return SessionStatus(flag: try flag.read() ? .on : .off, session: session, message: nil)
        } catch {
            return SessionStatus(flag: .unknown, session: session, message: error.localizedDescription)
        }
    }

    private func begin(_ ownership: Ownership, lease: TimeInterval) {
        self.ownership = ownership
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
