import Foundation
import IOKit
import IOKit.pwr_mgt
import LidAwakeShared

/// One request to keep the Mac awake, as the system reports it.
public struct SleepRequest: Equatable {
    /// The kind of request, for example PreventUserIdleSystemSleep.
    public let kind: String
    public let processName: String
    /// Nil when the executable of the process could not be read.
    public let executablePath: String?

    public init(kind: String, processName: String, executablePath: String?) {
        self.kind = kind
        self.processName = processName
        self.executablePath = executablePath
    }
}

/// One reading of everything that makes the Mac count as working.
public struct BusySample: Equatable {
    /// Core-seconds spent outside the idle state since the Mac started;
    /// nil when the counter could not be read.
    public let cpuBusySeconds: Double?
    /// Seconds since the last keyboard or mouse input; nil when it could not be read.
    public let inputIdleSeconds: Double?
    /// Every request the Mac holds right now, nothing left out;
    /// nil when the requests could not be read.
    public let sleepRequests: [SleepRequest]?

    public init(cpuBusySeconds: Double?, inputIdleSeconds: Double?, sleepRequests: [SleepRequest]?) {
        self.cpuBusySeconds = cpuBusySeconds
        self.inputIdleSeconds = inputIdleSeconds
        self.sleepRequests = sleepRequests
    }
}

public protocol BusySignalSource {
    /// Path the program and its helper run from; requests from inside it never count.
    var ownPathPrefix: String? { get }
    func read() -> BusySample
}

/// Which sleep requests count as work.
public enum BusyRules {
    /// Requests that hold off system sleep. Requests of any other kind, display-only ones included,
    /// never count.
    public static let countedKinds: Set<String> = [
        "PreventUserIdleSystemSleep",
        "PreventSystemSleep",
        "NoIdleSleepAssertion",
    ]

    /// Programs that come with macOS hold requests of their own the whole time, so the directories
    /// they run from are left out. A request without a readable path is left out too: an unreadable
    /// signal counts as an absent one.
    public static let systemPaths = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
        "/sbin/",
    ]

    public static func counts(_ request: SleepRequest, ownPathPrefix: String?) -> Bool {
        guard countedKinds.contains(request.kind), let path = request.executablePath else { return false }
        if let ownPathPrefix, path.hasPrefix(ownPathPrefix) { return false }
        return !systemPaths.contains { path.hasPrefix($0) }
    }

    /// Names of the processes whose requests count, each one once, in the order they came in.
    public static func holders(in requests: [SleepRequest], ownPathPrefix: String?) -> [String] {
        var names: [String] = []
        for request in requests where counts(request, ownPathPrefix: ownPathPrefix) {
            if !names.contains(request.processName) {
                names.append(request.processName)
            }
        }
        return names
    }
}

/// Reads the signals from macOS itself, with documented calls only and without starting any program.
public struct SystemBusySignals: BusySignalSource {
    public let ownPathPrefix: String?

    public init(ownPathPrefix: String? = SystemBusySignals.enclosingBundlePath()) {
        self.ownPathPrefix = ownPathPrefix
    }

    public func read() -> BusySample {
        BusySample(
            cpuBusySeconds: Self.cpuBusySeconds(),
            inputIdleSeconds: Self.inputIdleSeconds(),
            sleepRequests: Self.sleepRequests()
        )
    }

    /// The bundle this binary runs from, so its own requests and those of the program next to it are
    /// left out without naming either. Falls back to the directory of the binary.
    public static func enclosingBundlePath() -> String? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        var directory = executable.deletingLastPathComponent()
        while directory.path != "/" {
            if directory.pathExtension == "app" {
                return directory.path + "/"
            }
            directory = directory.deletingLastPathComponent()
        }
        return executable.deletingLastPathComponent().path + "/"
    }

    // Every core gets this many ticks per second, so busy ticks divided by the rate are core-seconds:
    // eight cores busy for a second give eight.
    private static let ticksPerSecond: Double = {
        let rate = sysconf(_SC_CLK_TCK)
        return rate > 0 ? Double(rate) : 100
    }()

    static func cpuBusySeconds() -> Double? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let nice = Double(info.cpu_ticks.3)
        return (user + system + nice) / ticksPerSecond
    }

    // The window server is tied to a login session, so the idle time comes from the driver itself.
    static func inputIdleSeconds() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }
        guard let nanoseconds = property.takeRetainedValue() as? NSNumber else { return nil }
        return nanoseconds.doubleValue / 1_000_000_000
    }

    static func sleepRequests() -> [SleepRequest]? {
        var copied: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&copied) == kIOReturnSuccess,
              let byProcess = copied?.takeRetainedValue() as? [AnyHashable: Any] else {
            return nil
        }
        var requests: [SleepRequest] = []
        for (key, value) in byProcess {
            guard let pid = (key as? NSNumber)?.int32Value,
                  let held = value as? [[AnyHashable: Any]] else {
                continue
            }
            let path = executablePath(of: pid)
            let name = processName(of: pid) ?? path.map { ($0 as NSString).lastPathComponent } ?? ""
            for request in held {
                guard let kind = request[kIOPMAssertionTypeKey] as? String else { continue }
                requests.append(SleepRequest(kind: kind, processName: name, executablePath: path))
            }
        }
        return requests
    }

    static func executablePath(of pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE, which Swift does not import.
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processName(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
}

/// Processor time one process has spent since it started.
public struct ProcessTime: Equatable {
    public let pid: Int32
    /// When the process started, so a number reused by a new process is not taken for the old one.
    public let startTime: UInt64
    public let name: String
    /// In the system's own units; only compared with other readings.
    public let cpuTime: UInt64
    public let parentPID: Int32
    /// The executable; nil when it could not be read.
    public let path: String?
    /// Processor seconds of the process and of its children that have ended and been reaped.
    public let cpuSecondsWithReaped: Double

    public init(
        pid: Int32,
        startTime: UInt64,
        name: String,
        cpuTime: UInt64,
        parentPID: Int32 = 0,
        path: String? = nil,
        cpuSecondsWithReaped: Double = 0
    ) {
        self.pid = pid
        self.startTime = startTime
        self.name = name
        self.cpuTime = cpuTime
        self.parentPID = parentPID
        self.path = path
        self.cpuSecondsWithReaped = cpuSecondsWithReaped
    }

    public var snapshot: ProcessSnapshot {
        ProcessSnapshot(pid: pid, startTime: startTime, parentPID: parentPID, path: path, cpuSeconds: cpuSecondsWithReaped)
    }
}

public protocol ProcessTimeSource {
    /// Every process that could be read; nil when the list itself could not be read.
    func read() -> [ProcessTime]?
}

/// Reads the processes with documented calls only. Running as root, it sees every process.
public struct SystemProcessTimes: ProcessTimeSource {
    public init() {}

    public func read() -> [ProcessTime]? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return nil }
        return pids.prefix(Int(count)).compactMap(Self.time(of:))
    }

    private static func time(of pid: pid_t) -> ProcessTime? {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        let name = proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
        let cpuTime = usage.ri_user_time + usage.ri_system_time
        let reaped = usage.ri_child_user_time + usage.ri_child_system_time
        return ProcessTime(
            pid: pid,
            startTime: usage.ri_proc_start_abstime,
            name: name,
            cpuTime: cpuTime,
            parentPID: parentPID(of: pid) ?? 0,
            path: SystemBusySignals.executablePath(of: pid),
            cpuSecondsWithReaped: Double(cpuTime + reaped) * secondsPerUnit
        )
    }

    private static func parentPID(of pid: pid_t) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }

    // The times come in ticks of the absolute clock: nanoseconds on Intel, not on Apple silicon.
    private static let secondsPerUnit: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return 1e-9 }
        return Double(timebase.numer) / Double(timebase.denom) / 1e9
    }()
}

public enum BusiestProcess {
    /// The process that spent the most processor time between two readings. A process missing from
    /// the first reading started in between and counts from zero; one missing from the second has
    /// ended and does not count. Nil when either reading is missing or nothing spent any time.
    public static func name(from start: [ProcessTime]?, to end: [ProcessTime]?) -> String? {
        guard let start, let end else { return nil }
        var before: [ProcessKey: UInt64] = [:]
        for process in start {
            before[ProcessKey(process)] = process.cpuTime
        }
        var busiest: (name: String, spent: UInt64)?
        for process in end where !process.name.isEmpty {
            let previous = before[ProcessKey(process)] ?? 0
            guard process.cpuTime > previous else { continue }
            let spent = process.cpuTime - previous
            if let current = busiest, current.spent > spent || (current.spent == spent && current.name <= process.name) {
                continue
            }
            busiest = (process.name, spent)
        }
        return busiest?.name
    }

    private struct ProcessKey: Hashable {
        let pid: Int32
        let startTime: UInt64

        init(_ process: ProcessTime) {
            pid = process.pid
            startTime = process.startTime
        }
    }
}
