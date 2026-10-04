import Foundation

public protocol SessionClock {
    /// Seconds on a monotonic timeline.
    var now: TimeInterval { get }
}

/// Monotonic and unaffected by changes to the wall clock; keeps counting while the Mac sleeps.
public struct MonotonicClock: SessionClock {
    public init() {}

    public var now: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}
