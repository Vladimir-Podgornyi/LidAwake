import XCTest
@testable import LidAwakeCore

@MainActor
private final class FakeInstaller: HelperInstalling {
    var state: HelperState
    var isInApplications = true
    /// The state registration leaves behind.
    var stateAfterInstall: HelperState = .ready
    private(set) var calls: [String] = []

    init(_ state: HelperState) {
        self.state = state
    }

    func refresh() async {
        calls.append("refresh")
    }

    func install() async {
        calls.append("install")
        state = stateAfterInstall
    }

    func openSystemSettings() {
        calls.append("settings")
    }
}

@MainActor
private final class FakeClock {
    var now: TimeInterval = 1000
    private(set) var sleeps = 0

    func sleep() async {
        sleeps += 1
        now += 2
        await Task.yield()
    }
}

@MainActor
final class HelperSetupTests: XCTestCase {
    private let clock = FakeClock()
    private var selected: [Mode] = []
    private var dismissals = 0
    private var wakeSyncs = 0

    private func makeSetup(_ helper: FakeInstaller) -> HelperSetup {
        let clock = self.clock
        return HelperSetup(
            helper: helper,
            dismissModeMessage: { [unowned self] in self.dismissals += 1 },
            selectMode: { [unowned self] in self.selected.append($0) },
            syncWake: { [unowned self] in self.wakeSyncs += 1 },
            pollSleep: { await clock.sleep() },
            approvalTimeout: 300,
            now: { clock.now }
        )
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<5000 where !done() {
            await Task.yield()
        }
    }

    private func waitingForApproval() async -> (FakeInstaller, HelperSetup) {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .requiresApproval
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        return (helper, setup)
    }

    func testNoPromptBeforeModeIsChosen() {
        let helper = FakeInstaller(.notInstalled)
        let setup = makeSetup(helper)
        XCTAssertNil(setup.prompt)
        XCTAssertFalse(setup.isWaiting)
        XCTAssertEqual(helper.calls, [])
    }

    func testChoosingAnyModeDismissesModeMessage() async {
        let (_, setup) = await waitingForApproval()
        XCTAssertEqual(setup.prompt, .approval)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(selected, [])

        await setup.select(.off)
        XCTAssertEqual(dismissals, 2)
        await setup.select(.keepScreenOn)
        XCTAssertEqual(dismissals, 3)
    }

    func testReadyHelperStartsModeAtOnce() async {
        let helper = FakeInstaller(.ready)
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(helper.calls, ["refresh"])
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
        XCTAssertFalse(setup.isWaiting)
    }

    func testMissingHelperIsRegisteredAndModeStarts() async {
        let helper = FakeInstaller(.notInstalled)
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(helper.calls, ["refresh", "install"])
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
    }

    func testOutdatedHelperIsReinstalledAndModeStarts() async {
        let helper = FakeInstaller(.outdated(6))
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(helper.calls, ["refresh", "install"])
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
    }

    func testApprovalPromptThenModeStartsOnApproval() async {
        let (helper, setup) = await waitingForApproval()
        XCTAssertEqual(setup.prompt, .approval)
        XCTAssertTrue(setup.isWaiting)
        XCTAssertEqual(selected, [])

        await setup.performPromptAction()
        XCTAssertEqual(helper.calls.last, "settings")

        helper.state = .ready
        await settle { !selected.isEmpty }
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
        XCTAssertFalse(setup.isWaiting)
        XCTAssertGreaterThanOrEqual(clock.sleeps, 1)
    }

    func testApprovalIsCheckedEveryTwoSeconds() async {
        let (helper, setup) = await waitingForApproval()
        await settle { clock.sleeps >= 3 }
        let refreshes = helper.calls.filter { $0 == "refresh" }.count
        XCTAssertGreaterThanOrEqual(refreshes, 3)
        XCTAssertEqual(clock.now, 1000 + 2 * Double(clock.sleeps))
        XCTAssertTrue(setup.isWaiting)
        XCTAssertEqual(selected, [])
    }

    func testOutsideApplicationsNothingIsRegistered() async {
        let helper = FakeInstaller(.notInstalled)
        helper.isInApplications = false
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(helper.calls, ["refresh"])
        XCTAssertEqual(setup.prompt, .moveToApplications)
        XCTAssertEqual(
            setup.prompt?.text,
            "Run with Lid Closed needs the app in the Applications folder."
        )
        XCTAssertFalse(setup.isWaiting)
        XCTAssertEqual(selected, [])
    }

    func testRegistrationFailureShowsErrorAndRetries() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .error("Registration failed.")
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(setup.prompt, .failed("Registration failed."))
        XCTAssertEqual(setup.prompt?.actionTitle, "Try Again")
        XCTAssertFalse(setup.isWaiting)
        XCTAssertEqual(selected, [])

        helper.stateAfterInstall = .ready
        await setup.performPromptAction()
        XCTAssertEqual(helper.calls, ["refresh", "install", "refresh", "install"])
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
    }

    func testSilentHelperShowsError() async {
        let helper = FakeInstaller(.error("The helper did not respond."))
        helper.stateAfterInstall = .error("The helper did not respond.")
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(setup.prompt, .failed("The helper did not respond."))
        XCTAssertEqual(selected, [])
    }

    func testRegistrationWithoutEffectShowsError() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .notInstalled
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(setup.prompt, .failed("The helper could not be installed."))
        XCTAssertEqual(selected, [])
    }

    func testOtherModeCancelsWaiting() async {
        for mode in [Mode.off, .keepScreenOn] {
            selected = []
            let (helper, setup) = await waitingForApproval()
            await setup.select(mode)
            XCTAssertNil(setup.prompt, "\(mode)")
            XCTAssertFalse(setup.isWaiting, "\(mode)")
            XCTAssertEqual(selected, [mode])

            helper.state = .ready
            let sleeps = clock.sleeps
            await settle { clock.sleeps > sleeps + 3 }
            XCTAssertEqual(selected, [mode], "\(mode)")
        }
    }

    func testTimeoutDropsAutomaticStart() async {
        let (helper, setup) = await waitingForApproval()
        XCTAssertEqual(setup.prompt, .approval)
        await settle { !setup.isWaiting }
        XCTAssertFalse(setup.isWaiting)
        XCTAssertEqual(setup.prompt, .approvalExpired)
        XCTAssertEqual(setup.prompt?.action, .openSystemSettings)
        XCTAssertEqual(clock.sleeps, 150)

        helper.state = .ready
        for _ in 0..<100 {
            await Task.yield()
        }
        XCTAssertEqual(clock.sleeps, 150)
        XCTAssertEqual(selected, [])
    }

    func testSettingsButtonWorksAfterTimeout() async {
        let (helper, setup) = await waitingForApproval()
        await settle { !setup.isWaiting }
        await setup.performPromptAction()
        XCTAssertEqual(helper.calls.last, "settings")
        XCTAssertEqual(setup.prompt, .approvalExpired)
    }

    func testChoosingModeAgainAfterTimeoutStartsReadyHelper() async {
        let (helper, setup) = await waitingForApproval()
        await settle { !setup.isWaiting }
        helper.state = .ready
        await setup.select(.lidClosed)
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertNil(setup.prompt)
    }

    // MARK: Wake at

    func testWakeWithReadyHelperAgreesAtOnceAndLeavesTheMode() async {
        let helper = FakeInstaller(.ready)
        let setup = makeSetup(helper)
        await setup.requestWake()
        XCTAssertEqual(helper.calls, ["refresh"])
        XCTAssertEqual(wakeSyncs, 1)
        XCTAssertEqual(selected, [])
        XCTAssertNil(setup.prompt)
    }

    func testWakeTakesTheApprovalPathWithoutTurningTheModeOn() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .requiresApproval
        let setup = makeSetup(helper)
        await setup.requestWake()
        XCTAssertEqual(helper.calls, ["refresh", "install"])
        XCTAssertEqual(setup.prompt, .approval, "the same message as for Run with Lid Closed")
        XCTAssertEqual(setup.prompt?.action, .openSystemSettings)
        XCTAssertFalse(setup.isWaiting, "no mode waits for the helper")
        XCTAssertEqual(wakeSyncs, 0)

        await setup.performPromptAction()
        XCTAssertEqual(helper.calls.last, "settings")

        helper.state = .ready
        await settle { wakeSyncs > 0 }
        XCTAssertEqual(wakeSyncs, 1, "the wake is agreed after the approval")
        XCTAssertEqual(selected, [], "the mode is not turned on")
        XCTAssertNil(setup.prompt)
    }

    func testWakeOutsideApplicationsShowsTheSameMessage() async {
        let helper = FakeInstaller(.notInstalled)
        helper.isInApplications = false
        let setup = makeSetup(helper)
        await setup.requestWake()
        XCTAssertEqual(setup.prompt, .moveToApplications)
        XCTAssertEqual(wakeSyncs, 0)
    }

    func testWakeTryAgainRetriesTheWake() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .error("Registration failed.")
        let setup = makeSetup(helper)
        await setup.requestWake()
        XCTAssertEqual(setup.prompt, .failed("Registration failed."))

        helper.stateAfterInstall = .ready
        await setup.performPromptAction()
        XCTAssertEqual(wakeSyncs, 1)
        XCTAssertEqual(selected, [])
        XCTAssertNil(setup.prompt)
    }

    func testChoosingAnotherModeKeepsTheWakeWaiting() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .requiresApproval
        let setup = makeSetup(helper)
        await setup.requestWake()
        await setup.select(.keepScreenOn)
        XCTAssertEqual(selected, [.keepScreenOn])
        XCTAssertEqual(setup.prompt, .approval)

        helper.state = .ready
        await settle { wakeSyncs > 0 }
        XCTAssertEqual(wakeSyncs, 1)
        XCTAssertEqual(selected, [.keepScreenOn])
    }

    func testTurningWakeOffDropsTheWait() async {
        let helper = FakeInstaller(.notInstalled)
        helper.stateAfterInstall = .requiresApproval
        let setup = makeSetup(helper)
        await setup.requestWake()
        setup.cancelWake()
        XCTAssertNil(setup.prompt)

        helper.state = .ready
        let sleeps = clock.sleeps
        await settle { clock.sleeps > sleeps + 3 }
        XCTAssertEqual(wakeSyncs, 0)
    }

    func testWakeDuringTheModeWaitIsAgreedWhenTheModeStarts() async {
        let (helper, setup) = await waitingForApproval()
        await setup.requestWake()
        XCTAssertTrue(setup.isWaiting, "the mode keeps waiting")
        XCTAssertEqual(helper.calls.filter { $0 == "install" }.count, 1)

        helper.state = .ready
        await settle { wakeSyncs > 0 }
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertEqual(wakeSyncs, 1)
    }

    func testModeAloneDoesNotAgreeTheWake() async {
        let helper = FakeInstaller(.ready)
        let setup = makeSetup(helper)
        await setup.select(.lidClosed)
        XCTAssertEqual(selected, [.lidClosed])
        XCTAssertEqual(wakeSyncs, 0)
    }
}
