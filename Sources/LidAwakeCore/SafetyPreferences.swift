import Combine
import Foundation
import LidAwakeShared

@MainActor
public final class SafetyPreferences: ObservableObject {
    public enum Key {
        public static let timerEnabled = "timerEnabled"
        public static let timerSeconds = "timerSeconds"
        public static let batteryLimitEnabled = "batteryLimitEnabled"
        public static let batteryLimitPercent = "batteryLimitPercent"
        public static let thermalProtectionEnabled = "thermalProtectionEnabled"
        public static let chargingOnlyEnabled = "chargingOnlyEnabled"
        public static let lockOnLidCloseEnabled = "lockOnLidCloseEnabled"
        public static let idleSleepEnabled = "idleSleepEnabled"
        public static let idleSleepMinutes = "idleSleepMinutes"
        public static let watchedAppPaths = "watchedAppPaths"
        public static let timerSetForWatchedApps = "timerSetForWatchedApps"
        public static let watchedAppsTimerPending = "watchedAppsTimerPending"
        public static let watchedAppsTimerConsidered = "watchedAppsTimerConsidered"
        public static let watchedAppsTimerMigrated = "watchedAppsTimerMigrated"
    }

    public static let timerChoices = [1800, 3600, 7200, 14_400, 28_800]
    /// Set the first time Sleep when idle is on with watched apps and the timer off, so a stuck app
    /// cannot keep the Mac awake forever.
    public static let watchedAppsTimerSeconds = 14_400
    public static let batteryLimitChoices = [10, 20, 30, 40, 50]
    public static let idleSleepChoices = [10, 20, 30, 60]

    @Published public var timerEnabled: Bool {
        didSet {
            save(timerEnabled, Key.timerEnabled)
            if timerEnabled {
                watchedAppsTimerPending = false
            } else {
                timerSetForWatchedApps = false
            }
        }
    }
    @Published public var timerSeconds: Int {
        didSet { save(timerSeconds, Key.timerSeconds) }
    }
    @Published public var batteryLimitEnabled: Bool {
        didSet { save(batteryLimitEnabled, Key.batteryLimitEnabled) }
    }
    @Published public var batteryLimitPercent: Int {
        didSet { save(batteryLimitPercent, Key.batteryLimitPercent) }
    }
    @Published public var thermalProtectionEnabled: Bool {
        didSet { save(thermalProtectionEnabled, Key.thermalProtectionEnabled) }
    }
    @Published public var chargingOnlyEnabled: Bool {
        didSet { save(chargingOnlyEnabled, Key.chargingOnlyEnabled) }
    }
    @Published public var idleSleepEnabled: Bool {
        didSet {
            if idleSleepEnabled != oldValue, !changesIdleSleepForSession {
                idleSleepForSessionOnly = false
                if idleSleepEnabled {
                    considerWatchedAppsTimer()
                } else {
                    watchedAppsTimerPending = false
                }
            }
            save(idleSleepEnabled, Key.idleSleepEnabled)
        }
    }
    @Published public var idleSleepMinutes: Int {
        didSet { save(idleSleepMinutes, Key.idleSleepMinutes) }
    }
    /// Apps whose started programs count as work for Sleep when idle.
    @Published public var watchedAppPaths: [String] {
        didSet {
            if watchedAppPaths.isEmpty {
                timerSetForWatchedApps = false
                watchedAppsTimerPending = false
                watchedAppsTimerConsidered = false
            } else if oldValue.isEmpty {
                considerWatchedAppsTimer()
            }
            save(watchedAppPaths, Key.watchedAppPaths)
        }
    }
    /// The timer was turned on by adding the first watched app; cleared when the timer is turned off
    /// or the list is emptied. Not sent to the helper.
    @Published public private(set) var timerSetForWatchedApps: Bool {
        didSet { defaults.set(timerSetForWatchedApps, forKey: Key.timerSetForWatchedApps) }
    }
    /// Watched apps first met Sleep when idle while a mode was on; the 4-hour timer is set when the
    /// mode ends. Cleared when the timer is turned on, Sleep when idle is turned off or the list is
    /// emptied. Not sent to the helper.
    @Published public private(set) var watchedAppsTimerPending: Bool {
        didSet { defaults.set(watchedAppsTimerPending, forKey: Key.watchedAppsTimerPending) }
    }
    /// Sleep when idle and watched apps have met since the list was last empty, so the 4-hour timer
    /// is not offered again. Not sent to the helper.
    public private(set) var watchedAppsTimerConsidered: Bool {
        didSet { defaults.set(watchedAppsTimerConsidered, forKey: Key.watchedAppsTimerConsidered) }
    }
    /// Set by the mode controller. Ending a mode sets a pending watched-apps timer.
    public var modeIsOn = false {
        didSet {
            if !modeIsOn {
                applyPendingWatchedAppsTimer()
            }
        }
    }
    /// Not sent to the helper, so changing it does not fire `changes`.
    @Published public var lockOnLidCloseEnabled: Bool {
        didSet { defaults.set(lockOnLidCloseEnabled, forKey: Key.lockOnLidCloseEnabled) }
    }

    /// Sleep when idle was turned on by `beginIdleSleepSession`, not by the user.
    @Published public private(set) var idleSleepForSessionOnly = false

    /// Fires after any setting has changed.
    public let changes = PassthroughSubject<Void, Never>()

    private let defaults: UserDefaults
    private var sendsChanges = true
    private var changesIdleSleepForSession = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.timerEnabled: false,
            Key.timerSeconds: 7200,
            Key.batteryLimitEnabled: true,
            Key.batteryLimitPercent: 20,
            Key.thermalProtectionEnabled: true,
            Key.chargingOnlyEnabled: false,
            Key.lockOnLidCloseEnabled: true,
            Key.idleSleepEnabled: false,
            Key.idleSleepMinutes: 20,
            Key.watchedAppPaths: [String](),
            Key.timerSetForWatchedApps: false,
            Key.watchedAppsTimerPending: false,
            Key.watchedAppsTimerConsidered: false,
        ])
        timerEnabled = defaults.bool(forKey: Key.timerEnabled)
        timerSeconds = Self.clamp(defaults.integer(forKey: Key.timerSeconds), to: SafetySettings.timerRange)
        batteryLimitEnabled = defaults.bool(forKey: Key.batteryLimitEnabled)
        batteryLimitPercent = Self.clamp(
            defaults.integer(forKey: Key.batteryLimitPercent),
            to: SafetySettings.batteryLimitRange
        )
        thermalProtectionEnabled = defaults.bool(forKey: Key.thermalProtectionEnabled)
        chargingOnlyEnabled = defaults.bool(forKey: Key.chargingOnlyEnabled)
        lockOnLidCloseEnabled = defaults.bool(forKey: Key.lockOnLidCloseEnabled)
        idleSleepEnabled = defaults.bool(forKey: Key.idleSleepEnabled)
        idleSleepMinutes = Self.clamp(defaults.integer(forKey: Key.idleSleepMinutes), to: SafetySettings.idleSleepRange)
        watchedAppPaths = defaults.stringArray(forKey: Key.watchedAppPaths) ?? []
        timerSetForWatchedApps = defaults.bool(forKey: Key.timerSetForWatchedApps)
        watchedAppsTimerPending = defaults.bool(forKey: Key.watchedAppsTimerPending)
        watchedAppsTimerConsidered = defaults.bool(forKey: Key.watchedAppsTimerConsidered)
        migrateWatchedAppsTimer()
        // The app starts in Off; a mode that was on when it quit has ended.
        applyPendingWatchedAppsTimer()
    }

    /// The note under the Watched Apps list.
    public var showsWatchedAppsTimerNote: Bool {
        timerSetForWatchedApps && timerEnabled && !watchedAppPaths.isEmpty
    }

    /// The note under the Watched Apps list while the 4-hour timer waits for the mode to end.
    public var showsWatchedAppsTimerPendingNote: Bool {
        watchedAppsTimerPending && !timerEnabled && !watchedAppPaths.isEmpty
    }

    /// The timer applies in both modes; the other protections only in Run with Lid Closed.
    public var timerLimit: Int? {
        timerEnabled ? timerSeconds : nil
    }

    /// Only while charging already pauses the session on battery, so the battery limit is not used then.
    public var batteryLimitApplies: Bool {
        !chargingOnlyEnabled
    }

    public var helperSettings: SafetySettings {
        SafetySettings(
            timerSeconds: timerEnabled ? timerSeconds : 0,
            batteryLimitPercent: batteryLimitApplies && batteryLimitEnabled ? batteryLimitPercent : 0,
            thermalProtection: thermalProtectionEnabled,
            thermalStopAtFair: false,
            chargingOnly: chargingOnlyEnabled,
            idleSleepMinutes: idleSleepEnabled ? idleSleepMinutes : 0,
            watchedAppPaths: idleSleepEnabled ? Self.acceptedWatchedAppPaths(watchedAppPaths) : []
        )
    }

    /// Paths the helper would reject are left out rather than failing the session; repeats are sent once.
    static func acceptedWatchedAppPaths(_ paths: [String]) -> [String] {
        var accepted: [String] = []
        for path in paths where WatchedApps.isValidPath(path) && !accepted.contains(path) {
            accepted.append(path)
        }
        return Array(accepted.prefix(WatchedApps.maximumCount))
    }

    /// Turns Sleep when idle on for a session about to start, which reads the setting itself,
    /// so `changes` does not fire.
    public func beginIdleSleepSession() {
        guard !idleSleepEnabled else { return }
        sendsChanges = false
        changesIdleSleepForSession = true
        defer {
            sendsChanges = true
            changesIdleSleepForSession = false
        }
        idleSleepEnabled = true
        idleSleepForSessionOnly = true
    }

    /// Sleep when idle lasts one Run with Lid Closed session. The session has already ended, so there is
    /// nothing to send to the helper and `changes` does not fire.
    public func endIdleSleepSession() {
        guard idleSleepEnabled else { return }
        sendsChanges = false
        changesIdleSleepForSession = true
        defer {
            sendsChanges = true
            changesIdleSleepForSession = false
        }
        idleSleepEnabled = false
        idleSleepForSessionOnly = false
    }

    /// Called when Sleep when idle is turned on or the first app is added. The caller's save sends
    /// the one change for every setting touched here.
    private func considerWatchedAppsTimer() {
        guard idleSleepEnabled, !idleSleepForSessionOnly, !watchedAppPaths.isEmpty, !watchedAppsTimerConsidered else {
            return
        }
        watchedAppsTimerConsidered = true
        guard !timerEnabled else { return }
        // The timer counts from the start of the mode, so turning it on now could end a long
        // session at once.
        if modeIsOn {
            watchedAppsTimerPending = true
        } else {
            let sends = sendsChanges
            sendsChanges = false
            setWatchedAppsTimer()
            sendsChanges = sends
        }
    }

    /// A list kept from a version without the 4-hour timer was chosen without it, so the timer is
    /// never set for that list. Runs once; an emptied and refilled list follows the usual rule.
    private func migrateWatchedAppsTimer() {
        guard !defaults.bool(forKey: Key.watchedAppsTimerMigrated) else { return }
        defaults.set(true, forKey: Key.watchedAppsTimerMigrated)
        if !watchedAppPaths.isEmpty {
            watchedAppsTimerConsidered = true
            defaults.set(true, forKey: Key.watchedAppsTimerConsidered)
        }
    }

    private func setWatchedAppsTimer() {
        timerSeconds = Self.watchedAppsTimerSeconds
        timerEnabled = true
        timerSetForWatchedApps = true
    }

    private func applyPendingWatchedAppsTimer() {
        guard watchedAppsTimerPending else { return }
        watchedAppsTimerPending = false
        guard !timerEnabled, !watchedAppPaths.isEmpty else { return }
        let sends = sendsChanges
        sendsChanges = false
        setWatchedAppsTimer()
        sendsChanges = sends
        if sendsChanges {
            changes.send()
        }
    }

    /// A stored value the helper would reject is read as the nearest one it accepts.
    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        if sendsChanges {
            changes.send()
        }
    }
}
