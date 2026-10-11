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
    /// Events kept until the app takes them; older ones make room for newer.
    public static let eventCapacity = 200

    private typealias CPUPoint = (at: TimeInterval, busySeconds: Double)

    private let source: BusySignalSource
    private let clock: SessionClock
    private let processes: ProcessTimeSource
    private let wallClock: () -> Date

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
    /// Names of the programs whose requests counted in this minute.
    private var holderNamesThisMinute: Set<String> = []
    /// What the last decided minute came down to; nil until a minute is decided after a restart.
    private var lastCause: IdleCause?
    /// Process times at the start of the minute; read only while the count runs.
    private var processesAtMinuteStart: [ProcessTime]?
    private var events: [IdleEvent] = []

    public init(
        source: BusySignalSource,
        clock: SessionClock,
        processes: ProcessTimeSource,
        wallClock: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.clock = clock
        self.processes = processes
        self.wallClock = wallClock
    }

    public func sample() {
        let now = clock.now
        let reading = source.read()
        let holders = reading.sleepRequests.map {
            BusyRules.holders(in: $0, ownPathPrefix: source.ownPathPrefix)
        }
        if let holders, !holders.isEmpty {
            sawHolderThisMinute = true
            holderNamesThisMinute.formUnion(holders)
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
        holderNamesThisMinute = []
        lastCause = nil
        processesAtMinuteStart = requiredMinutes > 0 ? processes.read() : nil
        // The counter reading is up to one reading old, so the load of the first minute can come out
        // slightly high. That can only keep the Mac awake, never put it to sleep too early.
        minuteStart = (at: clock.now, busySeconds: window.last?.busySeconds)
    }

    /// Hands over the events collected since the last call and forgets them.
    public func takeEvents() -> [IdleEvent] {
        defer { events = [] }
        return events
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
            let processesNow = processes.read()
            note(cause(
                holder: sawHolderThisMinute,
                input: busyByInput,
                load: busyByLoad,
                processes: processesNow
            ))
            processesAtMinuteStart = processesNow
        }
        minuteStart = (at: now, busySeconds: reading.cpuBusySeconds)
        sawHolderThisMinute = false
        holderNamesThisMinute = []
    }

    /// What the minute just counted came down to, checked in the order of the count rules above.
    /// Nil for a minute busy by load that did not clear the count: it changes nothing.
    private func cause(holder: Bool, input: Bool, load: Bool, processes processesNow: [ProcessTime]?) -> IdleCause? {
        if holder {
            let names = holderNamesThisMinute
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .app(names.min() ?? "")
        }
        if input {
            return .input
        }
        if load {
            guard loadMinutesInARow >= Self.loadMinutesBeforeReset else { return nil }
            return .load(busiest: BusiestProcess.name(from: processesAtMinuteStart, to: processesNow))
        }
        return .idle(minutes: requiredMinutes)
    }

    /// Records a change only: the same cause minute after minute is one event.
    private func note(_ cause: IdleCause?) {
        guard let cause, !Self.isSame(cause, as: lastCause) else { return }
        lastCause = cause
        events.append(IdleEvent(time: wallClock(), cause: cause))
        if events.count > Self.eventCapacity {
            events.removeFirst(events.count - Self.eventCapacity)
        }
    }

    // The busiest process may change from minute to minute while the load stays the reason.
    private static func isSame(_ cause: IdleCause, as previous: IdleCause?) -> Bool {
        switch (cause, previous) {
        case (.load, .load?):
            return true
        default:
            return cause == previous
        }
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
