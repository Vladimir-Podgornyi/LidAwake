import Foundation

/// One process as the watched-app rules see it.
public struct ProcessSnapshot: Equatable {
    public let pid: Int32
    /// When the process started, so a number reused by a new process is not taken for the old one.
    public let startTime: UInt64
    public let parentPID: Int32
    /// The executable; nil when it could not be read.
    public let path: String?
    /// Processor seconds the process has spent, together with its children that have ended and been reaped.
    public let cpuSeconds: Double

    public init(pid: Int32, startTime: UInt64, parentPID: Int32, path: String?, cpuSeconds: Double) {
        self.pid = pid
        self.startTime = startTime
        self.parentPID = parentPID
        self.path = path
        self.cpuSeconds = cpuSeconds
    }
}

/// What one watched app's started programs did between two readings.
public struct WatchedAppReading: Equatable {
    public let path: String
    /// Seconds spent by the group that spent the most; 0 when the app started nothing.
    public let busiestGroupSeconds: Double
    public let isBusy: Bool

    public init(path: String, busiestGroupSeconds: Double, isBusy: Bool) {
        self.path = path
        self.busiestGroupSeconds = busiestGroupSeconds
        self.isBusy = isBusy
    }
}

/// Apps whose started programs count as work: a terminal or an editor stays busy by itself, so only
/// what it started is measured.
///
/// A group is a process whose parent runs from inside the app's folder while its own executable lies
/// outside it, together with all its descendants, wherever their executables lie.
public enum WatchedApps {
    public static let maximumCount = 20

    /// At most `maximumCount` paths, each absolute and ending in `.app`.
    public static func isValid(_ paths: [String]) -> Bool {
        paths.count <= maximumCount && paths.allSatisfy(isValidPath)
    }

    public static func isValidPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.hasSuffix(".app") && !name(ofAppAt: path).isEmpty
    }

    /// The folder name without `.app`.
    public static func name(ofAppAt path: String) -> String {
        let folder = (path as NSString).lastPathComponent
        return folder.hasSuffix(".app") ? String(folder.dropLast(4)) : folder
    }

    /// One reading per path, in the order given. An app is busy when one of its groups spent more than
    /// `busyAboveSeconds`; the groups are never added up.
    public static func readings(
        appPaths: [String],
        from start: [ProcessSnapshot],
        to end: [ProcessSnapshot],
        busyAboveSeconds: Double
    ) -> [WatchedAppReading] {
        appPaths.map { path in
            let busiest = groupSeconds(appPath: path, from: start, to: end).max() ?? 0
            return WatchedAppReading(path: path, busiestGroupSeconds: busiest, isBusy: busiest > busyAboveSeconds)
        }
    }

    /// Seconds each group of the app spent between the readings. The groups are taken from `end`.
    /// A process missing from `start` began in between and counts from zero; one missing from `end`
    /// has ended and adds nothing, except through the reaped time of its parent.
    public static func groupSeconds(appPath: String, from start: [ProcessSnapshot], to end: [ProcessSnapshot]) -> [Double] {
        var before: [ProcessKey: Double] = [:]
        for process in start {
            before[ProcessKey(process)] = process.cpuSeconds
        }
        return groups(appPath: appPath, in: end).map { members in
            members.reduce(0) { total, process in
                total + max(0, process.cpuSeconds - (before[ProcessKey(process)] ?? 0))
            }
        }
    }

    static func groups(appPath: String, in processes: [ProcessSnapshot]) -> [[ProcessSnapshot]] {
        let folder = appPath.hasSuffix("/") ? appPath : appPath + "/"
        var byPID: [Int32: ProcessSnapshot] = [:]
        var children: [Int32: [ProcessSnapshot]] = [:]
        for process in processes {
            byPID[process.pid] = process
            if process.parentPID != process.pid {
                children[process.parentPID, default: []].append(process)
            }
        }
        func isInside(_ process: ProcessSnapshot) -> Bool {
            process.path?.hasPrefix(folder) ?? false
        }
        // An unreadable path cannot start a group: the app's own processes would count otherwise.
        func startsGroup(_ process: ProcessSnapshot) -> Bool {
            guard let path = process.path else { return false }
            return !path.hasPrefix(folder)
        }
        func hasInsideAncestor(_ process: ProcessSnapshot) -> Bool {
            var seen: Set<Int32> = [process.pid]
            var current = process
            while let parent = byPID[current.parentPID], seen.insert(parent.pid).inserted {
                if isInside(parent) { return true }
                current = parent
            }
            return false
        }
        func subtree(_ root: ProcessSnapshot) -> [ProcessSnapshot] {
            var members: [ProcessSnapshot] = []
            var seen: Set<Int32> = []
            var pending = [root]
            while let process = pending.popLast() {
                guard seen.insert(process.pid).inserted else { continue }
                members.append(process)
                pending += children[process.pid] ?? []
            }
            return members
        }

        // The app's own processes are walked down from the topmost ones, so an app process started
        // inside a group stays part of that group and starts no groups of its own.
        var groups: [[ProcessSnapshot]] = []
        var seen: Set<Int32> = []
        var pending = processes.filter { isInside($0) && !hasInsideAncestor($0) }
        while let process = pending.popLast() {
            guard seen.insert(process.pid).inserted else { continue }
            for child in children[process.pid] ?? [] {
                if startsGroup(child) {
                    groups.append(subtree(child))
                } else {
                    pending.append(child)
                }
            }
        }
        return groups
    }

    private struct ProcessKey: Hashable {
        let pid: Int32
        let startTime: UInt64

        init(_ process: ProcessSnapshot) {
            pid = process.pid
            startTime = process.startTime
        }
    }
}
