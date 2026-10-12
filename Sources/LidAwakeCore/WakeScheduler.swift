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
    private var preferenceChanges: AnyCancellable?
    private var generation = 0

    public init(
        preferences: WakePreferences,
        helper: HelperPreparing,
        service: ScheduledWakeService,
        mode: ScheduledModeStarting,
        log: ActivityLogging,
        clockMonitor: ClockChangeMonitoring = SystemClockChangeMonitor(),
        now: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.helper = helper
        self.service = service
        self.mode = mode
        self.log = log
        self.clockMonitor = clockMonitor
        self.now = now
        preferenceChanges = preferences.changes.sink { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
    }

    public func start() {
        clockMonitor.start { [weak self] in
            Task { @MainActor in await self?.sync() }
        }
    }

    /// True when the setting is on and `time` is within the window around a wake the helper reported.
    public func isScheduledWake(at time: Date) -> Bool {
        guard preferences.wakeEnabled else { return false }
        return scheduledWakes.contains {
            time >= $0.addingTimeInterval(-Self.earliestBeforeWake) && time <= $0.addingTimeInterval(Self.latestAfterWake)
        }
    }

    public func macDidWake() {
        guard isScheduledWake(at: now()) else {
            log.record(.wake)
            Task { await sync() }
            return
        }
        log.record(.scheduledWake)
        // The display goes dark about nine seconds after the wake, so the mode comes first.
        Task {
            await mode.turnOnBySchedule()
            await sync()
        }
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
            scheduledWakes = wakes
            lastError = nil
        } catch {
            guard current == generation else { return }
            lastError = error.localizedDescription
        }
    }
}
