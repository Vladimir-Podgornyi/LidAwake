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

/// Monotonic and stopped while the Mac sleeps.
public struct AwakeClock: SessionClock {
    public init() {}

    public var now: TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
    }
}
