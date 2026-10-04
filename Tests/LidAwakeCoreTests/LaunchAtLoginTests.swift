import XCTest
@testable import LidAwakeCore

private struct RegistrationFailed: Error {}

private final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    var registerError: Error?
    /// The status a successful registration leaves behind.
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var calls: [String] = []

    func register() throws {
        calls.append("register")
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        status = .notRegistered
    }
}

private final class FakeStore: LaunchAtLoginStore {
    var isInitialized = false
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private let service = FakeLoginItem()
    private let store = FakeStore()
    private let installed = URL(fileURLWithPath: "/Applications/LidAwake.app")
    private let elsewhere = URL(fileURLWithPath: "/Users/someone/Downloads/LidAwake.app")

    private func make(bundleURL: URL? = nil) -> LaunchAtLogin {
        LaunchAtLogin(service: service, store: store, bundleURL: bundleURL ?? installed)
    }

    func testFirstLaunchInApplicationsRegistersAndMarks() {
        let launch = make()
        launch.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, ["register"])
        XCTAssertTrue(store.isInitialized)
        XCTAssertTrue(launch.isEnabled)
        XCTAssertNil(launch.notice)
    }

    func testFirstLaunchOutsideApplicationsDoesNothing() {
        let launch = make(bundleURL: elsewhere)
        launch.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, [])
        XCTAssertFalse(store.isInitialized)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .moveToApplications)
        XCTAssertEqual(launch.notice?.text, "Move LidAwake to the Applications folder to launch it at login.")
    }

    func testFailedFirstRegistrationDoesNotMark() {
        service.registerError = RegistrationFailed()
        let launch = make()
        launch.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, ["register"])
        XCTAssertFalse(store.isInitialized)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .turnOnInSettings)
    }

    func testAlreadyEnabledOnFirstLaunchMarksWithoutRegistering() {
        service.status = .enabled
        let launch = make()
        launch.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, [])
        XCTAssertTrue(store.isInitialized)
        XCTAssertTrue(launch.isEnabled)
    }

    func testMarkedLaunchDoesNotTurnLoginItemBackOn() {
        store.isInitialized = true
        service.status = .notRegistered
        let launch = make()
        launch.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, [])
        XCTAssertFalse(launch.isEnabled)
        XCTAssertNil(launch.notice)
    }

    func testToggleTurnsOnAndOff() {
        store.isInitialized = true
        let launch = make()
        XCTAssertFalse(launch.isEnabled)

        launch.setEnabled(true)
        XCTAssertTrue(launch.isEnabled)
        XCTAssertEqual(service.status, .enabled)

        launch.setEnabled(false)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(service.calls, ["register", "unregister"])
    }

    func testTurningOffByHandIsKeptOnNextLaunch() {
        let launch = make()
        launch.enableOnFirstLaunch()
        launch.setEnabled(false)

        let next = make()
        next.enableOnFirstLaunch()
        XCTAssertEqual(service.calls, ["register", "unregister"])
        XCTAssertFalse(next.isEnabled)
    }

    func testRequiresApprovalLeavesToggleOffWithNotice() {
        store.isInitialized = true
        service.statusAfterRegister = .requiresApproval
        let launch = make()

        launch.setEnabled(true)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .turnOnInSettings)
        XCTAssertEqual(
            launch.notice?.text,
            "Turn it on in System Settings > General > Login Items & Extensions."
        )
    }

    func testFailedToggleLeavesToggleOffWithNotice() {
        store.isInitialized = true
        service.registerError = RegistrationFailed()
        let launch = make()

        launch.setEnabled(true)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .turnOnInSettings)
    }

    func testStatusIsReadFromSystemOnRefresh() {
        let launch = make()
        launch.enableOnFirstLaunch()
        XCTAssertTrue(launch.isEnabled)

        // Turned off in System Settings while the app runs.
        service.status = .requiresApproval
        launch.refresh()
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .turnOnInSettings)
    }

    func testToggleDoesNothingOutsideApplications() {
        let launch = make(bundleURL: elsewhere)
        launch.setEnabled(true)
        XCTAssertEqual(service.calls, [])
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(launch.notice, .moveToApplications)
    }
}
