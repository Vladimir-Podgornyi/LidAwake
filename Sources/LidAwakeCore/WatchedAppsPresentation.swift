import Darwin
import Foundation
import LidAwakeShared

/// The rows of the SLEEP AND WAKE section, top to bottom.
public enum SleepAndWakeRow: Hashable {
    case wakeAt
    /// Dimmed where the mode cannot use it.
    case sleepWhenIdle(isDimmed: Bool)
    /// Opens the Watched Apps window; works in every position.
    case watchedApps

    public static func list(mode: Mode) -> [SleepAndWakeRow] {
        [.wakeAt, .sleepWhenIdle(isDimmed: SafetyLayout(mode: mode) == .timerOnly), .watchedApps]
    }
}

/// The line under Watched apps: the chosen apps in the order they were chosen.
public enum WatchedAppsSummary {
    public static func text(paths: [String], name: (String) -> String) -> String {
        let names = paths.map(name).filter { !$0.isEmpty }
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }
}

/// An app running on the Mac, as the window needs it.
public struct RunningApp: Equatable {
    public let path: String
    public let name: String
    public let bundleIdentifier: String?
    /// An ordinary app with a Dock icon and windows, not a background agent.
    public let isRegular: Bool

    public init(path: String, name: String, bundleIdentifier: String?, isRegular: Bool) {
        self.path = path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isRegular = isRegular
    }
}

public struct WatchedAppEntry: Equatable, Identifiable {
    public let path: String
    public let name: String
    public let isWatched: Bool

    public var id: String { path }

    public init(path: String, name: String, isWatched: Bool) {
        self.path = path
        self.name = name
        self.isWatched = isWatched
    }
}

/// What the Watched Apps window lists.
public struct WatchedAppList: Equatable {
    /// Ordinary apps that are running, by name.
    public let open: [WatchedAppEntry]
    /// Chosen apps that are not running, by name.
    public let notOpen: [WatchedAppEntry]

    public init(open: [WatchedAppEntry], notOpen: [WatchedAppEntry]) {
        self.open = open
        self.notOpen = notOpen
    }

    /// LidAwake itself is left out by its identifier and its path. `name` gives the name of a chosen
    /// app that is not running. Apps in `turnedOff` that are not running stay in Watched, not open
    /// with the switch off.
    public static func make(
        running: [RunningApp],
        watched: [String],
        turnedOff: [String] = [],
        ownBundleIdentifier: String?,
        ownPath: String?,
        name: (String) -> String
    ) -> WatchedAppList {
        func isOwn(_ path: String, _ identifier: String?) -> Bool {
            (identifier != nil && identifier == ownBundleIdentifier) || path == ownPath
        }
        var open: [WatchedAppEntry] = []
        var openPaths: Set<String> = []
        for app in running where app.isRegular && WatchedApps.isValidPath(app.path) && !isOwn(app.path, app.bundleIdentifier) {
            // A second copy of the same app is the same row.
            guard openPaths.insert(app.path).inserted else { continue }
            let title = app.name.isEmpty ? name(app.path) : app.name
            open.append(WatchedAppEntry(path: app.path, name: title, isWatched: watched.contains(app.path)))
        }
        var notOpen: [WatchedAppEntry] = []
        for path in watched + turnedOff where !openPaths.contains(path) && !isOwn(path, nil) {
            guard !notOpen.contains(where: { $0.path == path }) else { continue }
            notOpen.append(WatchedAppEntry(path: path, name: name(path), isWatched: watched.contains(path)))
        }
        return WatchedAppList(open: sorted(open), notOpen: sorted(notOpen))
    }

    private static func sorted(_ entries: [WatchedAppEntry]) -> [WatchedAppEntry] {
        entries.sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0.path < $1.path
            }
        }
    }
}

public enum WatchedAppSelection {
    /// The list after a switch was flipped: a new app goes to the end, at most
    /// `WatchedApps.maximumCount` apps are kept, and a path is never there twice.
    public static func setting(_ path: String, isOn: Bool, in paths: [String]) -> [String] {
        if isOn {
            guard !paths.contains(path), paths.count < WatchedApps.maximumCount, WatchedApps.isValidPath(path) else {
                return paths
            }
            return paths + [path]
        }
        return paths.filter { $0 != path }
    }

    /// A switch that is off cannot be turned on once the list is full.
    public static func canAdd(to paths: [String]) -> Bool {
        paths.count < WatchedApps.maximumCount
    }

    /// The list after Space on a row: the app's switch flipped, with the same limits.
    public static func toggling(_ path: String, in paths: [String]) -> [String] {
        setting(path, isOn: !paths.contains(path), in: paths)
    }
}

/// Apps turned off in Watched, not open while the window is open. They keep their rows until the
/// window closes, so the row under the keys does not go away and Space can turn it back on.
public struct WatchedAppsTurnedOff: Equatable {
    public private(set) var paths: [String]

    public init(paths: [String] = []) {
        self.paths = paths
    }

    /// The chosen apps after the switch of `path` was set to `isOn`, with the limits of
    /// `WatchedAppSelection`.
    public mutating func setting(_ path: String, isOn: Bool, in watched: [String], list: WatchedAppList) -> [String] {
        if !isOn, !paths.contains(path), list.notOpen.contains(where: { $0.path == path }) {
            paths.append(path)
        }
        return WatchedAppSelection.setting(path, isOn: isOn, in: watched)
    }

    /// Space on a row: the switch of `path` flipped.
    public mutating func toggling(_ path: String, in watched: [String], list: WatchedAppList) -> [String] {
        setting(path, isOn: !watched.contains(path), in: watched, list: list)
    }

    /// The window closed; it opens again without these rows.
    public mutating func reset() {
        paths = []
    }
}

extension WatchedAppList {
    /// The rows the arrow keys go through, top to bottom across both sections; the headings are
    /// not rows.
    public var rowPaths: [String] {
        (open + notOpen).map(\.path)
    }
}

/// The row the keyboard is on in the Watched Apps window.
public struct WatchedAppCursor: Equatable {
    public private(set) var rows: [String]
    public private(set) var selected: String?

    public init(rows: [String] = [], selected: String? = nil) {
        self.rows = rows
        self.selected = selected.flatMap { rows.contains($0) ? $0 : nil }
    }

    /// The list got the keys: the row chosen before stays, otherwise the first row is chosen.
    public mutating func enter() {
        if selected == nil {
            selected = rows.first
        }
    }

    /// One row up for a negative offset, down for a positive one; stops at the ends.
    public mutating func move(by offset: Int) {
        guard let selected, let index = rows.firstIndex(of: selected) else {
            self.selected = rows.first
            return
        }
        self.selected = rows[min(max(index + offset, 0), rows.count - 1)]
    }

    /// The list changed. The chosen app keeps the choice, also when it moved to the other section;
    /// when it left the list, the choice goes to the next row that is still there, or else the one
    /// before.
    public mutating func update(rows newRows: [String]) {
        defer { rows = newRows }
        guard let selected, !newRows.contains(selected) else { return }
        guard let index = rows.firstIndex(of: selected) else {
            self.selected = newRows.first
            return
        }
        let neighbours = rows[(index + 1)...] + rows[..<index].reversed()
        self.selected = neighbours.first(where: newRows.contains) ?? newRows.first
    }

    /// The window closed; it opens again with nothing chosen.
    public mutating func reset() {
        selected = nil
    }
}

/// Whether the programs each app started are working now, from the app's own readings of the
/// processes. A reading is compared with the oldest one of the last minute, the span the helper
/// counts over; until a minute has passed, the threshold shrinks with the span.
public struct WatchedAppActivity {
    public static let span: TimeInterval = 60

    private var readings: [(at: TimeInterval, processes: [ProcessSnapshot])] = []

    public init() {}

    /// Adds a reading taken at `time` and returns the apps of `appPaths` that are busy; nil until
    /// there are two readings to compare.
    public mutating func add(_ processes: [ProcessSnapshot], at time: TimeInterval, appPaths: [String]) -> Set<String>? {
        readings.removeAll { time - $0.at > Self.span }
        defer { readings.append((at: time, processes: processes)) }
        guard let start = readings.first, time > start.at else { return nil }
        let threshold = WatchedApps.busyGroupSeconds * min(1, (time - start.at) / Self.span)
        let busy = WatchedApps.readings(appPaths: appPaths, from: start.processes, to: processes, busyAboveSeconds: threshold)
        return Set(busy.filter(\.isBusy).map(\.path))
    }
}

/// Reads the processes of this user with documented calls; the processes of other users cannot
/// be read without the helper and are left out.
public enum UserProcessSnapshots {
    public static func read() -> [ProcessSnapshot]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return nil }
        return pids.prefix(Int(count)).compactMap(snapshot(of:))
    }

    private static func snapshot(of pid: pid_t) -> ProcessSnapshot? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let parent = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? Int32(bitPattern: info.pbi_ppid) : 0
        // PROC_PIDPATHINFO_MAXSIZE, which Swift does not import.
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
        let time = usage.ri_user_time + usage.ri_system_time + usage.ri_child_user_time + usage.ri_child_system_time
        return ProcessSnapshot(
            pid: pid,
            startTime: usage.ri_proc_start_abstime,
            parentPID: parent,
            path: path,
            cpuSeconds: Double(time) * secondsPerUnit
        )
    }

    // The times come in ticks of the absolute clock: nanoseconds on Intel, not on Apple silicon.
    private static let secondsPerUnit: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return 1e-9 }
        return Double(timebase.numer) / Double(timebase.denom) / 1e9
    }()
}
