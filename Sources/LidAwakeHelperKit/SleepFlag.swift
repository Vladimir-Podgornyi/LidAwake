import Foundation

public protocol SleepFlag {
    func read() throws -> Bool
    func write(_ value: Bool) throws
}

public enum SleepFlagError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case commandFailed(Int32)
    case timedOut
    case notApplied(expected: Bool)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Could not read SleepDisabled: \(detail)"
        case .commandFailed(let status):
            return "pmset exited with status \(status)."
        case .timedOut:
            return "pmset did not finish in time."
        case .notApplied(let expected):
            return "SleepDisabled did not change to \(expected ? 1 : 0)."
        }
    }
}

public enum PmsetOutput {
    /// Reads the SleepDisabled value from `pmset -g` output.
    ///
    /// pmset prints the line only once the setting exists in the system
    /// power settings; until then sleep is not disabled. A missing line counts
    /// as 0 only when the system-wide section is present.
    public static func sleepDisabled(in output: String) throws -> Bool {
        var sawSystemWide = false
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "System-wide power settings:" {
                sawSystemWide = true
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "SleepDisabled" else { continue }
            guard fields.count == 2 else {
                throw SleepFlagError.unreadable("unexpected line \"\(line)\"")
            }
            switch fields[1] {
            case "0": return false
            case "1": return true
            default: throw SleepFlagError.unreadable("unexpected value \"\(fields[1])\"")
            }
        }
        guard sawSystemWide else {
            throw SleepFlagError.unreadable("unexpected pmset output")
        }
        return false
    }
}

public struct CommandResult: Equatable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol CommandRunning {
    func run(_ path: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

public struct PmsetSleepFlag: SleepFlag {
    public static let pmsetPath = "/usr/bin/pmset"
    public static let timeout: TimeInterval = 10

    private let runner: CommandRunning

    public init(runner: CommandRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func read() throws -> Bool {
        let result = try runner.run(Self.pmsetPath, ["-g"], timeout: Self.timeout)
        guard result.status == 0 else {
            throw SleepFlagError.commandFailed(result.status)
        }
        return try PmsetOutput.sleepDisabled(in: result.output)
    }

    public func write(_ value: Bool) throws {
        let result = try runner.run(Self.pmsetPath, ["-a", "disablesleep", value ? "1" : "0"], timeout: Self.timeout)
        guard result.status == 0 else {
            throw SleepFlagError.commandFailed(result.status)
        }
        guard try read() == value else {
            throw SleepFlagError.notApplied(expected: value)
        }
    }
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ path: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        // Drain the pipe while the process runs so a full pipe cannot block it.
        var output = Data()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw SleepFlagError.timedOut
        }
        drained.wait()
        return CommandResult(status: process.terminationStatus, output: String(decoding: output, as: UTF8.self))
    }
}
