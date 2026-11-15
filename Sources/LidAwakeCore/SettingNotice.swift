import Combine
import Foundation
import LidAwakeShared

/// Lines under a setting that does nothing at the moment or was changed by another one.
/// They only explain; no setting changes because of them.
public enum SettingNotice {
    /// Under Watched apps, which is dimmed while the line shows.
    public static let watchedAppsUnused = String(localized: "Works only with Sleep when idle in Run with Lid Closed.")
    /// Under Wake at.
    public static let wakeOnBattery = String(localized: "The Mac is on battery, so the wake will not turn the mode on.")
    /// Under Sleep when idle.
    public static let idleSleepByWake = String(localized: "On for this session, turned on by Wake at.")
    /// Under Stop on low battery and Only while charging, which are dimmed while the line shows.
    public static let noBattery = String(localized: "This Mac has no battery.")

    /// Watched apps count only for Sleep when idle, which Keep Screen On does not use.
    public static func watchedAppsApply(mode: Mode, idleSleepEnabled: Bool) -> Bool {
        idleSleepEnabled && SafetyLayout(mode: mode) != .timerOnly
    }

    /// A Mac woken on battery does not turn Run with Lid Closed on.
    public static func showsWakeOnBattery(wakeEnabled: Bool, power: PowerSource) -> Bool {
        wakeEnabled && power == .battery
    }

    public static func showsIdleSleepByWake(idleSleepEnabled: Bool, forSessionOnly: Bool) -> Bool {
        idleSleepEnabled && forSessionOnly
    }

    public static func hasNoBattery(_ battery: BatteryLevel) -> Bool {
        battery == .none
    }

    /// The line under Turn off after while the 4-hour timer for watched apps is set or waits.
    public static func timer(setForWatchedApps: Bool, pendingForWatchedApps: Bool) -> String? {
        if setForWatchedApps {
            return String(localized: "Set to 4 hours for watched apps.")
        }
        if pendingForWatchedApps {
            return String(localized: "Will be set to 4 hours for watched apps when the mode ends.")
        }
        return nil
    }
}

/// The power source as the window shows it, read again each time the Mac switches between
/// battery and power.
@MainActor
public final class PowerStatus: ObservableObject {
    @Published public private(set) var reading: PowerReading

    private let source: PowerSourceReading
    private let monitor: PowerSourceMonitoring

    public init(
        source: PowerSourceReading = IOKitPowerSource(),
        monitor: PowerSourceMonitoring = IOKitPowerSourceMonitor()
    ) {
        self.source = source
        self.monitor = monitor
        reading = source.read()
        monitor.start { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func refresh() {
        let current = source.read()
        if current != reading {
            reading = current
        }
    }
}
