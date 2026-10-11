import Foundation
import LidAwakeShared

public protocol IdleWatching: AnyObject {
    /// Takes one reading and, once a minute of the Mac's working time has passed, counts that minute.
    func sample()
    /// 0 stops the count and clears it; any other number starts a fresh count.
    func require(minutes: Int)
    /// Starts the count from zero, keeping the required number of minutes.
    func restart()
    /// Minutes in a row in which the Mac did nothing.
    var countedMinutes: Int { get }
    /// What the helper sees right now; takes a reading of its own.
    func status() -> IdleStatus
}

/// Counts the minutes in which nothing worked on the Mac: the load stayed below the threshold,
/// no program asked the system to stay awake and nobody touched the keyboard or the mouse.
///
/// Not thread-safe: the helper calls it from one queue.
public final class IdleWatcher: IdleWatching {
    /// A minute counts as work above this many busy cores.
    public static let busyCores = 1.5
    /// The step of the count, in seconds of the Mac's working time.
    public static let minuteSeconds: TimeInterval = 60
    /// Input counts as work when it is this recent.
    public static let recentInputSeconds: TimeInterval = 60
    /// Minutes busy by load alone in a row that clear the count; fewer leave the count as it is.
    public static let loadMinutesBeforeReset = 3
    /// The load cannot be averaged over a shorter span than this.
    static let shortestLoadWindow: TimeInterval = 1

    private typealias CPUPoint = (at: TimeInterval, busySeconds: Double)

    private let source: BusySignalSource
    private let clock: SessionClock

    public private(set) var countedMinutes = 0
    private var requiredMinutes = 0
    private var loadMinutesInARow = 0
    /// Start of the minute being watched, with the counter reading it began from.
    private var minuteStart: (at: TimeInterval, busySeconds: Double?)?
    /// Counter readings of the last minute, oldest first.
    private var window: [CPUPoint] = []
    /// A request seen at any point in this minute counts for the whole minute, because requests
    /// come and go between readings.
    private var sawHolderThisMinute = false
    private var lastCores: Double?
    private var lastInputIdleSeconds: Double?
    private var lastHolders: [String]?

    public init(source: BusySignalSource, clock: SessionClock) {
        self.source = source
        self.clock = clock
    }

    public func sample() {
        let now = clock.now
        let reading = source.read()
        let holders = reading.sleepRequests.map {
            BusyRules.holders(in: $0, ownPathPrefix: source.ownPathPrefix)
        }
        if let holders, !holders.isEmpty {
            sawHolderThisMinute = true
        }

        window.removeAll { now - $0.at > Self.minuteSeconds }
        lastCores = Self.cores(from: window.first, to: reading.cpuBusySeconds, at: now)
        lastInputIdleSeconds = reading.inputIdleSeconds
        lastHolders = holders
        if let busySeconds = reading.cpuBusySeconds {
            window.append((at: now, busySeconds: busySeconds))
        }

        guard let minuteStart else {
            self.minuteStart = (at: now, busySeconds: reading.cpuBusySeconds)
            return
        }
        guard now - minuteStart.at >= Self.minuteSeconds else { return }
        count(minuteEndingAt: now, start: minuteStart, reading: reading)
    }

    public func require(minutes: Int) {
        guard minutes != requiredMinutes else { return }
        requiredMinutes = minutes
        restart()
    }

    public func restart() {
        countedMinutes = 0
        loadMinutesInARow = 0
        sawHolderThisMinute = false
        // The counter reading is up to one reading old, so the load of the first minute can come out
        // slightly high. That can only keep the Mac awake, never put it to sleep too early.
        minuteStart = (at: clock.now, busySeconds: window.last?.busySeconds)
    }

    public func status() -> IdleStatus {
        sample()
        return IdleStatus(
            state: state(),
            countedMinutes: countedMinutes,
            requiredMinutes: requiredMinutes,
            cores: lastCores,
            inputIdleSeconds: lastInputIdleSeconds,
            holders: lastHolders
        )
    }

    private func state() -> IdleState {
        guard requiredMinutes > 0 else { return .off }
        if let lastHolders, !lastHolders.isEmpty { return .busyApp }
        if let lastCores, lastCores > Self.busyCores { return .busyCPU }
        if let lastInputIdleSeconds, lastInputIdleSeconds < Self.recentInputSeconds { return .busyInput }
        return .counting
    }

    private func count(
        minuteEndingAt now: TimeInterval,
        start: (at: TimeInterval, busySeconds: Double?),
        reading: BusySample
    ) {
        let minuteCores = Self.cores(
            from: start.busySeconds.map { (at: start.at, busySeconds: $0) },
            to: reading.cpuBusySeconds,
            at: now
        )
        // A signal that could not be read counts as an absent one.
        let busyByLoad = minuteCores.map { $0 > Self.busyCores } ?? false
        let busyByInput = reading.inputIdleSeconds.map { $0 < Self.recentInputSeconds } ?? false

        if sawHolderThisMinute || busyByInput {
            countedMinutes = 0
            loadMinutesInARow = 0
        } else if busyByLoad {
            // Short bursts are forgiven; a Mac busy by load minute after minute is working.
            loadMinutesInARow += 1
            if loadMinutesInARow >= Self.loadMinutesBeforeReset {
                countedMinutes = 0
            }
        } else {
            countedMinutes += 1
            loadMinutesInARow = 0
        }

        if requiredMinutes == 0 {
            countedMinutes = 0
            loadMinutesInARow = 0
        } else {
            countedMinutes = min(countedMinutes, requiredMinutes)
        }
        minuteStart = (at: now, busySeconds: reading.cpuBusySeconds)
        sawHolderThisMinute = false
    }

    private static func cores(from start: CPUPoint?, to end: Double?, at now: TimeInterval) -> Double? {
        guard let start, let end else { return nil }
        let span = now - start.at
        guard span >= shortestLoadWindow else { return nil }
        let busy = end - start.busySeconds
        // The system counter is 32 bits wide and wraps around; a step back cannot be averaged.
        guard busy >= 0 else { return nil }
        return busy / span
    }
}
