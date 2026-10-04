import LidAwakeShared
import XCTest
@testable import LidAwakeCore

final class StatusLineTests: XCTestCase {
    private let eightyMinutes: TimeInterval = 80 * 60

    func testOffShowsNothing() {
        XCTAssertNil(StatusLine.text(mode: .off, isPaused: false, timerRemaining: nil, battery: .percent(82)))
    }

    func testKeepScreenOnWithoutTimer() {
        XCTAssertEqual(
            StatusLine.text(mode: .keepScreenOn, isPaused: false, timerRemaining: nil, battery: .percent(82)),
            "Screen stays on"
        )
    }

    func testKeepScreenOnWithTimer() {
        XCTAssertEqual(
            StatusLine.text(mode: .keepScreenOn, isPaused: false, timerRemaining: eightyMinutes, battery: .percent(82)),
            "1 h 20 min left"
        )
    }

    func testLidClosedWithTimer() {
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: eightyMinutes, battery: .percent(82)),
            "1 h 20 min left · Battery 82%"
        )
    }

    func testLidClosedWithoutTimer() {
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: nil, battery: .percent(82)),
            "Battery 82%"
        )
    }

    func testLidClosedPaused() {
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: true, timerRemaining: eightyMinutes, battery: .percent(82)),
            "Paused · on battery"
        )
    }

    func testUnreadableBattery() {
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: eightyMinutes, battery: .unknown),
            "1 h 20 min left · Battery unknown"
        )
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: nil, battery: .unknown),
            "Battery unknown"
        )
    }

    func testMacWithoutBattery() {
        XCTAssertEqual(
            StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: eightyMinutes, battery: .none),
            "1 h 20 min left"
        )
        XCTAssertNil(StatusLine.text(mode: .lidClosed, isPaused: false, timerRemaining: nil, battery: .none))
    }

    func testRemainingTimeRoundsUpToMinutes() {
        XCTAssertEqual(DurationFormat.remaining(1), "1 min")
        XCTAssertEqual(DurationFormat.remaining(45 * 60), "45 min")
        XCTAssertEqual(DurationFormat.remaining(7200), "2 h")
        XCTAssertEqual(DurationFormat.remaining(4741), "1 h 20 min")
    }
}

final class SafetyLayoutTests: XCTestCase {
    func testLayoutFollowsMode() {
        XCTAssertEqual(SafetyLayout(mode: .off), .all)
        XCTAssertEqual(SafetyLayout(mode: .lidClosed), .all)
        XCTAssertEqual(SafetyLayout(mode: .keepScreenOn), .timerOnly)
    }
}

final class WindowMessageTests: XCTestCase {
    private func only(helper: HelperPrompt? = nil, mode: ModeMessage? = nil) -> WindowMessage? {
        let messages = WindowMessage.list(helper: helper, mode: mode)
        XCTAssertEqual(messages.count, 1)
        return messages.first
    }

    func testNothingToSay() {
        XCTAssertEqual(WindowMessage.list(helper: nil, mode: nil), [])
    }

    func testApproval() {
        let message = only(helper: .approval)
        XCTAssertEqual(message?.kind, .actionNeeded)
        XCTAssertEqual(message?.title, "Permission needed")
        XCTAssertEqual(
            message?.text,
            "Allow LidAwake in System Settings > General > Login Items & Extensions. The mode turns on as soon as you do."
        )
        XCTAssertEqual(message?.action, .openSystemSettings)
        XCTAssertEqual(message?.actionTitle, "Open System Settings")
    }

    func testMoveToApplications() {
        let message = only(helper: .moveToApplications)
        XCTAssertEqual(message?.kind, .actionNeeded)
        XCTAssertEqual(message?.title, "Move LidAwake to Applications")
        XCTAssertEqual(message?.text, "Run with Lid Closed needs the app in the Applications folder.")
        XCTAssertNil(message?.action)
        XCTAssertNil(message?.actionTitle)
    }

    func testHelperFailed() {
        let message = only(helper: .failed("Broken"))
        XCTAssertEqual(message?.kind, .error)
        XCTAssertEqual(message?.title, "The helper did not start")
        XCTAssertEqual(message?.text, "Broken")
        XCTAssertEqual(message?.action, .tryAgain)
        XCTAssertEqual(message?.actionTitle, "Try Again")
    }

    func testCouldNotTurnOn() {
        let message = only(mode: .couldNotTurnOn("The battery is at 12%, at or below the 20% limit."))
        XCTAssertEqual(message?.kind, .error)
        XCTAssertEqual(message?.title, "Could not turn on")
        XCTAssertEqual(message?.text, "The battery is at 12%, at or below the 20% limit.")
        XCTAssertNil(message?.action)
        XCTAssertNil(message?.actionTitle)
    }

    func testTurnedOff() {
        let message = only(mode: .turnedOff("The timer ran out."))
        XCTAssertEqual(message?.kind, .info)
        XCTAssertEqual(message?.title, "LidAwake turned off")
        XCTAssertEqual(message?.text, "The timer ran out.")
        XCTAssertNil(message?.action)
        XCTAssertNil(message?.actionTitle)
    }

    func testTurnedOffWithError() {
        let message = only(mode: .turnedOffWithError("The helper did not respond."))
        XCTAssertEqual(message?.kind, .error)
        XCTAssertEqual(message?.title, "LidAwake turned off")
        XCTAssertEqual(message?.text, "The helper did not respond.")
        XCTAssertNil(message?.actionTitle)
    }

    func testFailed() {
        let message = only(mode: .failed("Broken"))
        XCTAssertEqual(message?.kind, .error)
        XCTAssertEqual(message?.title, "Something went wrong")
        XCTAssertEqual(message?.text, "Broken")
        XCTAssertNil(message?.actionTitle)
    }

    func testHelperMessageStandsAboveModeMessage() {
        let messages = WindowMessage.list(helper: .approval, mode: .turnedOff("The timer ran out."))
        XCTAssertEqual(messages.map(\.source), [.helper, .mode])
        XCTAssertEqual(messages.map(\.title), ["Permission needed", "LidAwake turned off"])
    }
}
