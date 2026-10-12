import Foundation
import LidAwakeCore
import LidAwakeShared

enum HelperCommand: Equatable {
    case status
    case install
    case uninstall
    case loginItemStatus
    /// The text after the flag: `HH:MM` or `off`.
    case scheduleWake(String)

    init?(arguments: [String]) {
        if arguments.contains("--login-item-status") {
            self = .loginItemStatus
        } else if let index = arguments.firstIndex(of: "--schedule-wake") {
            self = .scheduleWake(arguments.indices.contains(index + 1) ? arguments[index + 1] : "")
        } else if arguments.contains("--helper-status") {
            self = .status
        } else if arguments.contains("--install-helper") {
            self = .install
        } else if arguments.contains("--uninstall-helper") {
            self = .uninstall
        } else {
            return nil
        }
    }

    @MainActor
    func run() async -> Int32 {
        if self == .loginItemStatus {
            print("login-item=\(Self.token(for: MainAppLoginItemService().status))")
            return 0
        }
        if case .scheduleWake(let text) = self {
            return await scheduleWake(text)
        }
        let service = DaemonHelperService()
        let connection = XPCHelperConnection()
        let client = HelperClient(service: service, connection: connection)

        switch self {
        case .status, .loginItemStatus, .scheduleWake:
            break
        case .install:
            await client.install()
        case .uninstall:
            await client.uninstall()
        }

        if case .error(let message) = client.state, self != .status {
            printError("error: \(message)")
            return 1
        }

        let registration = service.registration
        var line = Self.token(for: registration)
        var build = HelperBuildStatus.unknown
        do {
            let version = try await connection.protocolVersion()
            line += " protocol=\(version)"
            if version == HelperConstants.protocolVersion {
                build = await client.buildStatus()
                let status = try await connection.sessionStatus()
                line += " sleep-disabled=\(status.flag.token) session=\(status.session.token)"
                line += " paused=\(status.paused ? "yes" : "no")"
                line += " timer=\(status.timerRemaining.map(String.init) ?? "off")"
                line += " battery=\(status.power.battery.token) power=\(status.power.source.token)"
                line += " thermal=\(status.thermal.token)"
                let idle = try await Self.idleStatus(from: connection)
                line += " idle=\(idle.token) cores=\(idle.coresToken)"
                line += " input=\(idle.inputToken) holders=\(idle.holdersToken)"
                line += " \(ScheduledWake.statusField(try? await connection.scheduledWakes()))"
            }
        } catch {
            printError("helper: \(error.localizedDescription)")
        }
        if registration == .enabled || registration == .requiresApproval {
            line += " \(build.statusField)"
            line += " registration=\(client.isRegistrationCurrent ? "current" : "stale")"
        }
        print(line)
        return 0
    }

    /// Changes only the wakes the helper keeps, not the app's settings.
    private func scheduleWake(_ text: String) async -> Int32 {
        guard let minuteOfDay = ScheduledWake.minuteOfDay(from: text) else {
            printError("usage: --schedule-wake HH:MM (00:00 to 23:59) or --schedule-wake off")
            return 2
        }
        let connection = XPCHelperConnection()
        do {
            let version = try await connection.protocolVersion()
            guard version == HelperConstants.protocolVersion else {
                printError("error: the helper uses protocol \(version), this app needs \(HelperConstants.protocolVersion)")
                return 1
            }
            try await connection.setScheduledWake(minuteOfDay: minuteOfDay)
            print(ScheduledWake.statusField(try await connection.scheduledWakes()))
            return 0
        } catch {
            printError("error: \(error.localizedDescription)")
            return 1
        }
    }

    /// A helper that has just started has nothing to average the load over yet, so the command waits.
    private static func idleStatus(from connection: XPCHelperConnection) async throws -> IdleStatus {
        var status = try await connection.idleStatus()
        var attempts = 0
        while status.cores == nil, attempts < 2 {
            attempts += 1
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            status = try await connection.idleStatus()
        }
        return status
    }

    private static func token(for registration: HelperRegistration) -> String {
        switch registration {
        case .notRegistered: return "not-registered"
        case .requiresApproval: return "requires-approval"
        case .enabled: return "enabled"
        case .notFound: return "not-found"
        }
    }

    private static func token(for status: LoginItemStatus) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not-registered"
        case .requiresApproval: return "requires-approval"
        case .notFound: return "not-found"
        }
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
