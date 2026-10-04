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

public protocol LidSessionService {
    func startSession(leaseSeconds: Int, safety: SafetySettings) async throws
    func renewSession(leaseSeconds: Int, safety: SafetySettings) async throws
    func endSession() async throws
    func clearLeftover() async throws
    func sessionStatus() async throws -> HelperSessionStatus
    func lastStopReason() async throws -> StopRecord?
    func clearStopReason() async throws
}

public enum HelperError: Error, Equatable, LocalizedError {
    case notInApplications
    case timeout
    case connection(String)
    case notReady(String)
    case helper(HelperResultCode, String)

    public var errorDescription: String? {
        switch self {
        case .notInApplications:
            return String(localized: "LidAwake must be in /Applications to install the helper.")
        case .timeout:
            return String(localized: "The helper did not respond.")
        case .connection(let message), .notReady(let message), .helper(_, let message):
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
        FileManager.default.fileExists(atPath: HelperPlist.url(inBundle: Bundle.main.bundleURL).path)
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

public struct XPCHelperConnection: HelperConnecting, LidSessionService {
    private let timeout: TimeInterval
    private let sessionTimeout: TimeInterval

    // Session calls may run pmset twice with a 10 second limit each.
    public init(timeout: TimeInterval = 10, sessionTimeout: TimeInterval = 25) {
        self.timeout = timeout
        self.sessionTimeout = sessionTimeout
    }

    public func protocolVersion() async throws -> Int {
        try await call(timeout: timeout) { helper, done in
            helper.protocolVersion { done(.success($0)) }
        }
    }

    public func startSession(leaseSeconds: Int, safety: SafetySettings) async throws {
        try await call(timeout: sessionTimeout) { helper, done in
            helper.startSession(
                leaseSeconds: leaseSeconds,
                timerSeconds: safety.timerSeconds,
                batteryLimitPercent: safety.batteryLimitPercent,
                thermalProtection: safety.thermalProtection,
                chargingOnly: safety.chargingOnly
            ) { done(Self.result($0, $1)) }
        }
    }

    public func renewSession(leaseSeconds: Int, safety: SafetySettings) async throws {
        try await call(timeout: sessionTimeout) { helper, done in
            helper.renewSession(
                leaseSeconds: leaseSeconds,
                timerSeconds: safety.timerSeconds,
                batteryLimitPercent: safety.batteryLimitPercent,
                thermalProtection: safety.thermalProtection,
                chargingOnly: safety.chargingOnly
            ) { done(Self.result($0, $1)) }
        }
    }

    public func endSession() async throws {
        try await call(timeout: sessionTimeout) { helper, done in
            helper.endSession { done(Self.result($0, $1)) }
        }
    }

    public func clearLeftover() async throws {
        try await call(timeout: sessionTimeout) { helper, done in
            helper.clearLeftover { done(Self.result($0, $1)) }
        }
    }

    public func sessionStatus() async throws -> HelperSessionStatus {
        try await call(timeout: sessionTimeout) { helper, done in
            helper.sessionStatus { code, message, flag, session, timer, battery, source, thermal, paused in
                done(Self.result(code, message).flatMap {
                    guard let flag = SleepFlagState(rawValue: flag),
                          let session = SessionOwnership(rawValue: session),
                          let battery = BatteryLevel(wireValue: battery),
                          let source = PowerSource(rawValue: source),
                          let thermal = ThermalState(rawValue: thermal) else {
                        return .failure(HelperError.connection(String(localized: "Unexpected helper reply.")))
                    }
                    return .success(HelperSessionStatus(
                        flag: flag,
                        session: session,
                        timerRemaining: timer < 0 ? nil : timer,
                        power: PowerReading(battery: battery, source: source),
                        thermal: thermal,
                        paused: paused
                    ))
                })
            }
        }
    }

    public func lastStopReason() async throws -> StopRecord? {
        try await call(timeout: timeout) { helper, done in
            helper.lastStopReason { code, message, reason, time, percent in
                done(Self.result(code, message).flatMap {
                    guard let reason else { return .success(nil) }
                    guard let parsed = StopReason(rawValue: reason) else {
                        return .failure(HelperError.connection(String(localized: "Unexpected helper reply.")))
                    }
                    return .success(StopRecord(
                        reason: parsed,
                        time: Date(timeIntervalSince1970: time),
                        batteryPercent: percent < 0 ? nil : percent
                    ))
                })
            }
        }
    }

    public func clearStopReason() async throws {
        try await call(timeout: timeout) { helper, done in
            helper.clearStopReason { done(Self.result($0, $1)) }
        }
    }

    static func result(_ code: Int, _ message: String?) -> Result<Void, Error> {
        guard let code = HelperResultCode(rawValue: code) else {
            return .failure(HelperError.connection(String(localized: "Unexpected helper reply.")))
        }
        guard code == .ok else {
            return .failure(HelperError.helper(code, message ?? String(localized: "The helper reported error \(code.rawValue).")))
        }
        return .success(())
    }

    private func call<T>(
        timeout: TimeInterval,
        _ body: @escaping (HelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
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
                reply.resume(with: .failure(HelperError.connection(String(localized: "Unexpected helper interface."))))
                return
            }
            body(helper) { reply.resume(with: $0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                reply.resume(with: .failure(HelperError.timeout))
            }
        }
    }
}

// The XPC reply, the error handler and the timeout race; only the first may resume.
private final class SingleReply<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
