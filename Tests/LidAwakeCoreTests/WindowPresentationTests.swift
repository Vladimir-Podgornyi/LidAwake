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
    func testHiddenWhenReady() {
        XCTAssertNil(HelperPrompt(state: .ready))
    }

    func testShownWhenActionIsNeeded() {
        let states: [HelperState] = [.notInstalled, .requiresApproval, .outdated(6), .error("Broken")]
        for state in states {
            XCTAssertNotNil(HelperPrompt(state: state), "\(state)")
        }
    }

    func testActions() {
        XCTAssertEqual(HelperPrompt(state: .notInstalled)?.actionTitle, "Install Helper")
        XCTAssertEqual(HelperPrompt(state: .outdated(6))?.actionTitle, "Install Helper")
        XCTAssertEqual(HelperPrompt(state: .error("Broken"))?.actionTitle, "Install Helper")
        XCTAssertEqual(HelperPrompt(state: .requiresApproval)?.actionTitle, "Open System Settings")
        XCTAssertEqual(HelperPrompt(state: .error("Broken"))?.message, "Helper error: Broken")
    }
}
