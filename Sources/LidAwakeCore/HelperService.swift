import Foundation
import LidAwakeShared
import ServiceManagement

public enum HelperRegistration: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
}

public protocol HelperService {
    var registration: HelperRegistration { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

public protocol HelperConnecting {
    func protocolVersion() async throws -> Int
}

public enum HelperError: Error, Equatable, LocalizedError {
    case notInApplications
    case timeout
    case connection(String)

    public var errorDescription: String? {
        switch self {
        case .notInApplications:
            return "LidAwake must be in /Applications to install the helper."
        case .timeout:
            return "The helper did not respond."
        case .connection(let message):
            return message
        }
    }
}

public struct DaemonHelperService: HelperService {
    private let service = SMAppService.daemon(plistName: HelperConstants.plistName)

    public init() {}

    public var registration: HelperRegistration {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .enabled: return .enabled
        // A daemon that was never registered also reports notFound.
        case .notFound: return plistExists ? .notRegistered : .notFound
        @unknown default: return .notFound
        }
    }

    private var plistExists: Bool {
        let plist = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(HelperConstants.plistName)
        return FileManager.default.fileExists(atPath: plist.path)
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() async throws {
        try await service.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public struct XPCHelperConnection: HelperConnecting {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    public func protocolVersion() async throws -> Int {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.setCodeSigningRequirement(HelperConstants.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let reply = SingleReply(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                reply.resume(with: .failure(HelperError.connection(error.localizedDescription)))
            }
            guard let helper = proxy as? HelperProtocol else {
                reply.resume(with: .failure(HelperError.connection("Unexpected helper interface.")))
                return
            }
            helper.protocolVersion { version in
                reply.resume(with: .success(version))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                reply.resume(with: .failure(HelperError.timeout))
            }
        }
    }
}

// The XPC reply, the error handler and the timeout race; only the first may resume.
private final class SingleReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Error>?

    init(_ continuation: CheckedContinuation<Int, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Int, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
