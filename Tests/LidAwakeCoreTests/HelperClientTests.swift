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

private final class FakeStore: HelperRegistrationStore {
    var registrationDigest: String?

    init(_ digest: String?) {
        registrationDigest = digest
    }
}

@MainActor
final class HelperClientTests: XCTestCase {
    private let applications = URL(fileURLWithPath: "/Applications/LidAwake.app")
    private let elsewhere = URL(fileURLWithPath: "/Users/someone/Downloads/LidAwake.app")

    private var bundledPlist = "plist-v2"

    private func client(
        _ service: FakeService,
        _ connection: FakeConnection,
        bundle: URL? = nil,
        store: FakeStore = FakeStore("digest:plist-v2")
    ) -> HelperClient {
        HelperClient(
            service: service,
            connection: connection,
            bundleURL: bundle ?? applications,
            expectedVersion: 1,
            reinstallDelay: {},
            registrationStore: store,
            bundledPlist: { Data(self.bundledPlist.utf8) },
            digest: { "digest:" + String(decoding: $0, as: UTF8.self) }
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

    func testMatchingDigestIsReady() async {
        let sut = client(FakeService(.enabled), FakeConnection(1))
        await sut.refresh()
        XCTAssertEqual(sut.state, .ready)
        XCTAssertTrue(sut.isRegistrationCurrent)
    }

    func testMissingDigestIsOutdated() async {
        let sut = client(FakeService(.enabled), FakeConnection(1), store: FakeStore(nil))
        await sut.refresh()
        XCTAssertEqual(sut.state, .outdated(1))
        XCTAssertFalse(sut.isRegistrationCurrent)
    }

    func testDifferentDigestIsOutdated() async {
        let sut = client(FakeService(.enabled), FakeConnection(1), store: FakeStore("digest:plist-v1"))
        await sut.refresh()
        XCTAssertEqual(sut.state, .outdated(1))
        XCTAssertFalse(sut.isRegistrationCurrent)
    }

    func testReregistrationSavesNewDigest() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let store = FakeStore("digest:plist-v1")
        let sut = client(service, FakeConnection(1), store: store)
        await sut.install()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(store.registrationDigest, "digest:plist-v2")
        XCTAssertEqual(sut.state, .ready)
    }

    func testRegistrationAwaitingApprovalSavesDigest() async {
        let service = FakeService(.notRegistered)
        service.registerThrows = true
        let store = FakeStore(nil)
        let sut = client(service, FakeConnection(nil), store: store)
        await sut.install()
        XCTAssertEqual(store.registrationDigest, "digest:plist-v2")
    }

    func testFailedRegistrationKeepsDigest() async {
        let service = FakeService(.notRegistered)
        service.registerResult = .notRegistered
        service.registerThrows = true
        let store = FakeStore("digest:plist-v1")
        let sut = client(service, FakeConnection(nil), store: store)
        await sut.install()
        XCTAssertEqual(store.registrationDigest, "digest:plist-v1")
    }

    func testLaunchUpdatesStaleRegistration() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let store = FakeStore(nil)
        let sut = client(service, FakeConnection(1), store: store)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(store.registrationDigest, "digest:plist-v2")
        XCTAssertEqual(sut.state, .ready)
    }

    func testLaunchUpdatesOutdatedProtocol() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let connection = FakeConnection(2)
        service.onRegister = { connection.version = 1 }
        let sut = client(service, connection)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(sut.state, .ready)
    }

    func testLaunchKeepsCurrentRegistration() async {
        let service = FakeService(.enabled)
        let sut = client(service, FakeConnection(1))
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .ready)
    }

    func testLaunchSkipsUninstalledHelper() async {
        let service = FakeService(.notRegistered)
        let store = FakeStore(nil)
        let sut = client(service, FakeConnection(nil), store: store)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .notInstalled)
        XCTAssertNil(store.registrationDigest)
    }

    func testLaunchDoesNotRegisterHelperAwaitingApproval() async {
        let service = FakeService(.requiresApproval)
        let sut = client(service, FakeConnection(nil), store: FakeStore(nil))
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .requiresApproval)
    }

    func testLaunchOutsideApplicationsDoesNotReregister() async {
        let service = FakeService(.enabled)
        let store = FakeStore(nil)
        let sut = client(service, FakeConnection(1), bundle: elsewhere, store: store)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .error(HelperError.notInApplications.localizedDescription))
        XCTAssertNil(store.registrationDigest)
    }

    func testPrepareForSessionReregistersStaleRegistration() async throws {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let store = FakeStore("digest:plist-v1")
        let sut = client(service, FakeConnection(1), store: store)
        try await sut.prepareForSession()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(store.registrationDigest, "digest:plist-v2")
    }

    func testDigestIsSHA256OfPlist() {
        XCTAssertEqual(
            HelperPlist.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
