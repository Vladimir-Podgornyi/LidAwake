import Combine
import Foundation
import LidAwakeShared

public protocol ScheduledWakeService {
    func setScheduledWake(minuteOfDay: Int) async throws
    /// The wakes the helper scheduled, earliest first.
    func scheduledWakes() async throws -> [Date]
}

extension XPCHelperConnection: ScheduledWakeService {}

@MainActor
public protocol ScheduledModeStarting: AnyObject {
    /// Turns the mode on after the Mac woke on schedule, if the situation allows it.
    func turnOnBySchedule() async
}

public protocol ClockChangeMonitoring: AnyObject {
    /// Calls `handler` on the main thread when the system clock or time zone changes.
    func start(_ handler: @escaping () -> Void)
}

public final class SystemClockChangeMonitor: ClockChangeMonitoring {
    private var observers: [NSObjectProtocol] = []

    public init() {}

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func start(_ handler: @escaping () -> Void) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange].map {
            center.addObserver(forName: $0, object: nil, queue: .main) { _ in handler() }
        }
    }
}

public enum SystemBoot {
    /// When the system was started, from `kern.boottime`; nil if it cannot be read.
    public static func time() -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
    }
}

/// Keeps the helper's wakes in line with the setting and tells a wake on schedule from any other.
@MainActor
public final class WakeScheduler: ObservableObject, SystemWakeHandling {
    /// What the last call to the helper failed with; nil after a call that worked.
    @Published public private(set) var lastError: String?
    /// The wakes the helper reported after the last call that worked.
    @Published public private(set) var scheduledWakes: [Date] = []

    /// macOS reports the wake about a second after the scheduled time; the window allows for more.
    public static let earliestBeforeWake: TimeInterval = 10
    public static let latestAfterWake: TimeInterval = 120

    public let preferences: WakePreferences

    private let helper: HelperPreparing
    private let service: ScheduledWakeService
    private let mode: ScheduledModeStarting
    private let log: ActivityLogging
    private let clockMonitor: ClockChangeMonitoring
    private let now: () -> Date
    private let bootTime: () -> Date?
    private var preferenceChanges: AnyCancellable?
    private var generation = 0
    /// When the workspace last reported the Mac going to sleep; the dark wakes in between are not reported.
    private var lastSleep: Date?

    public init(
        preferences: WakePreferences,
        helper: HelperPreparing,
        service: ScheduledWakeService,
        mode: ScheduledModeStarting,
        log: ActivityLogging,
        clockMonitor: ClockChangeMonitoring = SystemClockChangeMonitor(),
        now: @escaping () -> Date = Date.init,
        bootTime: @escaping () -> Date? = SystemBoot.time
    ) {
        self.preferences = preferences
        self.helper = helper
        self.service = service
        self.mode = mode
        self.log = log
        self.clockMonitor = clockMonitor
        self.now = now
        self.bootTime = bootTime
        scheduledWakes = preferences.scheduledWakeTimes
        preferenceChanges = preferences.changes.sink { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
    }

    public func start() {
        clockMonitor.start { [weak self] in
            Task { @MainActor in await self?.syncIfNeeded() }
        }
    }

    /// Records the wakes missed while the Mac was turned off, then agrees with the helper.
    public func appDidLaunch() async {
        if let boot = bootTime() {
            recordMissedWakes { $0 < boot }
        }
        await syncIfNeeded()
    }

    /// Forgets the remembered wakes that have passed. Shutting down or restarting quits the app
    /// first, so at the next launch only the wakes that passed while it was not running are missed.
    public func appWillTerminate() {
        let current = now()
        remember(scheduledWakes.filter { $0 >= current })
    }

    /// True when the setting is on and `time` is within the window around a wake the helper reported.
    public func isScheduledWake(at time: Date) -> Bool {
        guard preferences.wakeEnabled else { return false }
        return scheduledWakes.contains {
            time >= $0.addingTimeInterval(-Self.earliestBeforeWake) && time <= $0.addingTimeInterval(Self.latestAfterWake)
        }
    }

    public func macWillSleep() {
        lastSleep = now()
    }

    public func macDidWake() {
        let asleepSince = lastSleep
        guard isScheduledWake(at: now()) else {
            log.record(.wake)
            recordMissedWakes(sleptSince: asleepSince)
            Task { await syncIfNeeded() }
            return
        }
        log.record(.scheduledWake)
        // The display goes dark about nine seconds after the wake, so the mode comes first.
        Task {
            await mode.turnOnBySchedule()
            recordMissedWakes(sleptSince: asleepSince)
            await sync()
        }
    }

    private func recordMissedWakes(sleptSince sleep: Date?) {
        recordMissedWakes { time in sleep.map { $0 < time } ?? false }
    }

    /// Records each remembered wake that passed more than `latestAfterWake` ago and that `missed`
    /// says the Mac slept through or was off for. Every such wake is then forgotten, so none is
    /// looked at twice, even if the helper cannot be reached to replace the list.
    private func recordMissedWakes(_ missed: (Date) -> Bool) {
        let cutoff = now().addingTimeInterval(-Self.latestAfterWake)
        let past = scheduledWakes.filter { $0 < cutoff }
        guard !past.isEmpty else { return }
        if preferences.wakeEnabled {
            for time in past where missed(time) {
                log.record(.modeSkipped(.lidClosed, .missed), at: time)
            }
        }
        remember(scheduledWakes.filter { $0 >= cutoff })
    }

    /// With the setting off and no wakes left there is nothing to schedule or cancel.
    private func syncIfNeeded() async {
        guard preferences.wakeEnabled || !scheduledWakes.isEmpty else { return }
        await sync()
    }

    private func remember(_ wakes: [Date]) {
        scheduledWakes = wakes
        preferences.scheduledWakeTimes = wakes
    }

    /// Sends the setting to the helper, if it is ready, and reads back the wakes it keeps.
    public func sync() async {
        guard await helper.isReady() else { return }
        generation += 1
        let current = generation
        let minuteOfDay = preferences.helperMinuteOfDay
        do {
            try await service.setScheduledWake(minuteOfDay: minuteOfDay)
            let wakes = try await service.scheduledWakes()
            // An answer to an older call must not replace a newer one.
            guard current == generation else { return }
            remember(wakes)
            lastError = nil
        } catch {
            guard current == generation else { return }
            lastError = error.localizedDescription
        }
    }
}
