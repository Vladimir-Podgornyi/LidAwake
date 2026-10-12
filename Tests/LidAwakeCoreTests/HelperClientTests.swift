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
    var build: String? = "build-b"
    var buildFails = false
    private(set) var buildReads = 0

    init(_ version: Int?) {
        self.version = version
    }

    func protocolVersion() async throws -> Int {
        guard let version else { throw HelperError.timeout }
        return version
    }

    func buildIdentifier() async throws -> String? {
        buildReads += 1
        if buildFails {
            throw HelperError.timeout
        }
        return build
    }
}

private final class FakeWakes: ScheduledWakeService {
    var setError: Error?
    private(set) var minutes: [Int] = []
    /// The service calls made before the wakes were cancelled.
    private(set) var serviceCallsAtSet: [[String]] = []
    var service: FakeService?

    func setScheduledWake(minuteOfDay: Int) async throws {
        minutes.append(minuteOfDay)
        serviceCallsAtSet.append(service?.calls ?? [])
        if let setError { throw setError }
    }

    func scheduledWakes() async throws -> [Date] { [] }
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
    private var bundledBuild: String? = "build-b"

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
            digest: { "digest:" + String(decoding: $0, as: UTF8.self) },
            bundledBuild: { self.bundledBuild }
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

    func testUninstallCancelsTheWakesBeforeUnregistering() async {
        let service = FakeService(.enabled)
        let wakes = FakeWakes()
        wakes.service = service
        let sut = client(service, FakeConnection(1))
        await sut.uninstall(cancelingWakesWith: wakes)
        XCTAssertEqual(wakes.minutes, [-1])
        XCTAssertEqual(wakes.serviceCallsAtSet, [[]], "the wakes go first")
        XCTAssertEqual(service.calls, ["unregister"])
        XCTAssertEqual(sut.state, .notInstalled)
    }

    func testUninstallUnregistersEvenWhenCancellingTheWakesFails() async {
        let service = FakeService(.enabled)
        let wakes = FakeWakes()
        wakes.setError = HelperError.timeout
        let sut = client(service, FakeConnection(1))
        await sut.uninstall(cancelingWakesWith: wakes)
        XCTAssertEqual(wakes.minutes, [-1])
        XCTAssertEqual(service.calls, ["unregister"])
        XCTAssertEqual(sut.state, .notInstalled)
    }

    func testUninstallLeavesTheWakesToAnotherProtocolOrASilentHelper() async {
        for version in [2, nil] as [Int?] {
            let service = FakeService(.enabled)
            let wakes = FakeWakes()
            let sut = client(service, FakeConnection(version))
            await sut.uninstall(cancelingWakesWith: wakes)
            XCTAssertEqual(wakes.minutes, [], "\(String(describing: version))")
            XCTAssertEqual(service.calls, ["unregister"])
        }
    }

    func testUninstallDoesNotChangeTheWakeSetting() async {
        let suite = "HelperClientTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WakePreferences(defaults: defaults)
        preferences.wakeEnabled = true
        let sut = client(FakeService(.enabled), FakeConnection(1))
        await sut.uninstall(cancelingWakesWith: FakeWakes())
        XCTAssertTrue(WakePreferences(defaults: defaults).wakeEnabled)
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

    func testMatchingBuildIsReady() async {
        let service = FakeService(.enabled)
        let sut = client(service, FakeConnection(1))
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .ready)
    }

    func testDifferentBuildIsOutdated() async {
        let connection = FakeConnection(1)
        connection.build = "build-a"
        let sut = client(FakeService(.enabled), connection)
        await sut.refresh()
        XCTAssertEqual(sut.state, .outdated(1))
    }

    func testLaunchReregistersHelperOfAnotherBuild() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let connection = FakeConnection(1)
        connection.build = "build-a"
        service.onRegister = { connection.build = "build-b" }
        let sut = client(service, connection)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(sut.state, .ready)
    }

    func testStillDifferentBuildIsReregisteredOnceAtLaunchAndOnceBeforeSession() async {
        let service = FakeService(.enabled)
        service.registerResult = .enabled
        let connection = FakeConnection(1)
        connection.build = "build-a"
        let sut = client(service, connection)
        await sut.updateIfOutdated()
        XCTAssertEqual(service.calls, ["unregister", "register"])
        XCTAssertEqual(sut.state, .outdated(1))

        do {
            try await sut.prepareForSession()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(
                error as? HelperError,
                .notReady(String(localized: "The helper could not be updated."))
            )
        }
        XCTAssertEqual(service.calls, ["unregister", "register", "unregister", "register"])
        XCTAssertEqual(sut.state, .outdated(1))
    }

    func testUnreadableRunningBuildIsNotOutdated() async {
        let service = FakeService(.enabled)
        let failing = FakeConnection(1)
        failing.buildFails = true
        let silent = FakeConnection(1)
        silent.build = nil
        for connection in [failing, silent] {
            let sut = client(service, connection)
            await sut.updateIfOutdated()
            XCTAssertEqual(sut.state, .ready)
        }
        XCTAssertEqual(service.calls, [])
    }

    func testUnreadableBundledBuildIsNotOutdated() async throws {
        bundledBuild = nil
        let service = FakeService(.enabled)
        let connection = FakeConnection(1)
        connection.build = "build-a"
        let sut = client(service, connection)
        try await sut.prepareForSession()
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(sut.state, .ready)
    }

    func testProtocolVersionIsCheckedBeforeBuild() async {
        let connection = FakeConnection(2)
        let sut = client(FakeService(.enabled), connection)
        await sut.refresh()
        XCTAssertEqual(sut.state, .outdated(2))
        XCTAssertEqual(connection.buildReads, 0)
    }

    func testBuildStatus() async {
        let connection = FakeConnection(1)
        let sut = client(FakeService(.enabled), connection)
        let current = await sut.buildStatus()
        XCTAssertEqual(current, .current)
        connection.build = "build-a"
        let stale = await sut.buildStatus()
        XCTAssertEqual(stale, .stale)
        connection.buildFails = true
        let unknown = await sut.buildStatus()
        XCTAssertEqual(unknown, .unknown)
    }

    func testBuildStatusField() {
        XCTAssertEqual(HelperBuildStatus.current.statusField, "build=current")
        XCTAssertEqual(HelperBuildStatus.stale.statusField, "build=stale")
        XCTAssertEqual(HelperBuildStatus.unknown.statusField, "build=unknown")
    }

    func testDigestIsSHA256OfPlist() {
        XCTAssertEqual(
            HelperPlist.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
