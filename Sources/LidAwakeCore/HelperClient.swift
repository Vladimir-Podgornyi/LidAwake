import Combine
import Foundation
import LidAwakeShared

public enum HelperState: Equatable {
    case notInstalled
    case requiresApproval
    case ready
    case error(String)
    case outdated(Int)
}

@MainActor
public protocol HelperPreparing: AnyObject {
    /// Reinstalls an outdated helper; throws when the helper still cannot serve a session.
    func prepareForSession() async throws
    func isReady() async -> Bool
}

@MainActor
public final class HelperClient: ObservableObject, HelperPreparing {
    @Published public private(set) var state: HelperState = .notInstalled
    @Published public private(set) var isBusy = false

    private let service: HelperService
    private let connection: HelperConnecting
    private let bundleURL: URL
    private let expectedVersion: Int
    private let reinstallDelay: () async -> Void

    public init(
        service: HelperService = DaemonHelperService(),
        connection: HelperConnecting = XPCHelperConnection(),
        bundleURL: URL = Bundle.main.bundleURL,
        expectedVersion: Int = HelperConstants.protocolVersion,
        reinstallDelay: @escaping () async -> Void = { try? await Task.sleep(nanoseconds: 2_000_000_000) }
    ) {
        self.service = service
        self.connection = connection
        self.bundleURL = bundleURL
        self.expectedVersion = expectedVersion
        self.reinstallDelay = reinstallDelay
    }

    public var isInApplications: Bool {
        bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path == "/Applications"
    }

    public func refresh() async {
        state = await currentState()
    }

    public func install() async {
        await perform {
            guard self.isInApplications else {
                throw HelperError.notInApplications
            }
            if self.service.registration == .enabled {
                if await self.currentState() == .ready {
                    return
                }
                try await self.service.unregister()
                await self.reinstallDelay()
            }
            do {
                try self.service.register()
            } catch where self.service.registration == .requiresApproval {
                // Registration succeeded; the user still has to approve it.
            }
        }
    }

    public func uninstall() async {
        await perform {
            try await self.service.unregister()
        }
    }

    public func prepareForSession() async throws {
        await refresh()
        if case .outdated = state {
            await install()
        }
        switch state {
        case .ready:
            return
        case .notInstalled:
            throw HelperError.notReady("Install the helper to run with the lid closed.")
        case .requiresApproval:
            throw HelperError.notReady("Allow LidAwake in System Settings > General > Login Items & Extensions.")
        case .outdated:
            throw HelperError.notReady("The helper could not be updated.")
        case .error(let message):
            throw HelperError.notReady(message)
        }
    }

    public func isReady() async -> Bool {
        await refresh()
        return state == .ready
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }

    private func perform(_ action: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
            state = await currentState()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func currentState() async -> HelperState {
        switch service.registration {
        case .notRegistered, .notFound:
            return .notInstalled
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            do {
                let version = try await connection.protocolVersion()
                return version == expectedVersion ? .ready : .outdated(version)
            } catch {
                return .error(error.localizedDescription)
            }
        }
    }
}
