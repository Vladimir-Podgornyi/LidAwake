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

final class HelperPromptTests: XCTestCase {
    func testMessages() {
        XCTAssertEqual(
            HelperPrompt.approval.message,
            "Allow LidAwake in System Settings > General > Login Items & Extensions."
        )
        XCTAssertEqual(
            HelperPrompt.moveToApplications.message,
            "Move LidAwake to the Applications folder to use Run with Lid Closed."
        )
        XCTAssertEqual(HelperPrompt.failed("Broken").message, "Broken")
    }

    func testActions() {
        XCTAssertEqual(HelperPrompt.approval.action, .openSystemSettings)
        XCTAssertEqual(HelperPrompt.approval.actionTitle, "Open System Settings")
        XCTAssertNil(HelperPrompt.moveToApplications.action)
        XCTAssertNil(HelperPrompt.moveToApplications.actionTitle)
        XCTAssertEqual(HelperPrompt.failed("Broken").action, .tryAgain)
        XCTAssertEqual(HelperPrompt.failed("Broken").actionTitle, "Try Again")
    }
}
