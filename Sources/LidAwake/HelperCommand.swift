import Foundation
import LidAwakeCore
import LidAwakeShared

enum HelperCommand {
    case status
    case install
    case uninstall

    init?(arguments: [String]) {
        if arguments.contains("--helper-status") {
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
        let service = DaemonHelperService()
        let connection = XPCHelperConnection()
        let client = HelperClient(service: service, connection: connection)

        switch self {
        case .status:
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

        var line = Self.token(for: service.registration)
        do {
            let version = try await connection.protocolVersion()
            line += " protocol=\(version)"
            if version == HelperConstants.protocolVersion {
                let status = try await connection.sessionStatus()
                line += " sleep-disabled=\(status.flag.token) session=\(status.session.token)"
                line += " timer=\(status.timerRemaining.map(String.init) ?? "off")"
                line += " battery=\(status.power.battery.token) power=\(status.power.source.token)"
            }
        } catch {
            printError("helper: \(error.localizedDescription)")
        }
        print(line)
        return 0
    }

    private static func token(for registration: HelperRegistration) -> String {
        switch registration {
        case .notRegistered: return "not-registered"
        case .requiresApproval: return "requires-approval"
        case .enabled: return "enabled"
        case .notFound: return "not-found"
        }
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
