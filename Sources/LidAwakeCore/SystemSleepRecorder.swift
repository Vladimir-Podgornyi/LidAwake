import AppKit

public protocol SystemSleepMonitoring: AnyObject {
    /// Calls `handler` on the main thread when the Mac goes to sleep (true) and when it wakes (false).
    func start(_ handler: @escaping (_ asleep: Bool) -> Void)
}

@MainActor
public protocol SystemWakeHandling: AnyObject {
    /// Records the wake in the log and acts on it.
    func macDidWake()
}

/// Writes the Mac going to sleep and waking up to the log, whatever mode is selected.
@MainActor
public final class SystemSleepRecorder {
    private let monitor: SystemSleepMonitoring
    private let log: ActivityLogging
    private weak var wakeHandler: SystemWakeHandling?

    /// With a `wakeHandler`, the handler records the wake instead.
    public init(
        monitor: SystemSleepMonitoring = WorkspaceSleepMonitor(),
        log: ActivityLogging,
        wakeHandler: SystemWakeHandling? = nil
    ) {
        self.monitor = monitor
        self.log = log
        self.wakeHandler = wakeHandler
    }

    public func start() {
        monitor.start { [weak self] asleep in
            MainActor.assumeIsolated { self?.changed(asleep: asleep) }
        }
    }

    private func changed(asleep: Bool) {
        if asleep {
            log.record(.sleep)
        } else if let wakeHandler {
            wakeHandler.macDidWake()
        } else {
            log.record(.wake)
        }
    }
}

/// Uses the workspace notifications, which macOS posts for a full sleep and wake but not for the
/// dark wakes it makes on its own while the display stays off.
public final class WorkspaceSleepMonitor: SystemSleepMonitoring {
    private var observers: [NSObjectProtocol] = []

    public init() {}

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }

    public func start(_ handler: @escaping (Bool) -> Void) {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                handler(true)
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                handler(false)
            },
        ]
    }
}
