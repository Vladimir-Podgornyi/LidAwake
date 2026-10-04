import XCTest
@testable import LidAwakeCore

private struct RegisterError: Error {}

private final class FakeService: HelperService {
    var registration: HelperRegistration
    var registerResult: HelperRegistration = .requiresApproval
    var registerThrows = false
    var onRegister: () -> Void = {}
    private(set) var calls: [String] = []

    init(_ registration: HelperRegistration) {
        self.registration = registration
    }

    func register() throws {
        calls.append("register")
        registration = registerResult
        onRegister()
        if registerThrows {
            throw RegisterError()
        }
    }

    func unregister() async throws {
        calls.append("unregister")
        registration = .notRegistered
    }

    func openSystemSettings() {
        calls.append("settings")
    }
}

private final class FakeConnection: HelperConnecting {
    var version: Int?

    init(_ version: Int?) {
        self.version = version
    }

    func protocolVersion() async throws -> Int {
        guard let version else { throw HelperError.timeout }
        return version
    }
}

@MainActor
final class HelperClientTests: XCTestCase {
    private let applications = URL(fileURLWithPath: "/Applications/LidAwake.app")
    private let elsewhere = URL(fileURLWithPath: "/Users/someone/Downloads/LidAwake.app")

    private func client(_ service: FakeService, _ connection: FakeConnection, bundle: URL? = nil) -> HelperClient {
        HelperClient(
            service: service,
            connection: connection,
            bundleURL: bundle ?? applications,
            expectedVersion: 1,
            reinstallDelay: {}
        )
    }

    func testStateMapping() async {
        let cases: [(HelperRegistration, Int?, HelperState)] = [
            (.notRegistered, nil, .notInstalled),
            (.notFound, nil, .notInstalled),
            (.requiresApproval, nil, .requiresApproval),
            (.enabled, 1, .ready),
            (.enabled, 2, .outdated(2)),
            (.enabled, nil, .error(HelperError.timeout.localizedDescription)),
        ]
        for (registration, version, expected) in cases {
            let sut = client(FakeService(registration), FakeConnection(version))
            await sut.refresh()
            XCTAssertEqual(sut.state, expected, "\(registration) \(String(describing: version))")
        }
    }

    func testRegisteredIsNotReadyWithoutReply() async {
        let sut = client(FakeService(.enabled), FakeConnection(nil))
        await sut.refresh()
        XCTAssertNotEqual(sut.state, .ready)
    }

    func testInstallOutsideApplicationsFails() async {
        let service = FakeService(.notRegistered)
        let sut = client(service, FakeConnection(nil), bundle: elsewhere)
        await sut.install()
        XCTAssertEqual(sut.state, .error(HelperError.notInApplications.localizedDescription))
        XCTAssertEqual(service.calls, [])
    }

    func testInstallWaitingForApproval() async {
        let service = FakeService(.notRegistered)
        service.registerThrows = true
        let sut = client(service, FakeConnection(nil))
        await sut.install()
        XCTAssertEqual(sut.state, .requiresApproval)
        XCTAssertEqual(service.calls, ["register"])
    }

    func testInstallFailure() async {
        let service = FakeService(.notRegistered)
        service.registerResult = .notRegistered
        service.registerThrows = true
        let sut = client(service, FakeConnection(nil))
        await sut.install()
        guard case .error = sut.state else {
            return XCTFail("expected error, got \(sut.state)")
        }
    }

    func testInstallReregistersOutdatedHelper() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let connection = FakeConnection(2)
        let sut = client(service, connection)
        await sut.refresh()
        XCTAssertEqual(sut.state, .outdated(2))

        service.onRegister = { connection.version = 1 }
        await sut.install()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(sut.state, .ready)
    }

    func testInstallReregistersSilentHelper() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let sut = client(service, FakeConnection(nil))
        await sut.install()
        XCTAssertEqual(service.calls, ["unregister", "register"])
    }

    func testInstallKeepsReadyHelper() async {
        let service = FakeService(.enabled)
        let sut = client(service, FakeConnection(1))
        await sut.install()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .ready)
    }

    func testUninstall() async {
        let service = FakeService(.enabled)
        let sut = client(service, FakeConnection(1))
        await sut.uninstall()
        XCTAssertEqual(service.calls, ["unregister"])
        XCTAssertEqual(sut.state, .notInstalled)
    }

    func testOpenSystemSettings() {
        let service = FakeService(.requiresApproval)
        client(service, FakeConnection(nil)).openSystemSettings()
        XCTAssertEqual(service.calls, ["settings"])
    }
}
