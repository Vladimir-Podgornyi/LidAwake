import Foundation
import XCTest
@testable import LidAwakeCore

final class AutoLogoutSourceTests: XCTestCase {
    private func delay(_ value: Any?) -> Int? {
        SystemAutoLogoutSource(read: { key in
            XCTAssertEqual(key, "com.apple.autologout.AutoLogOutDelay")
            return value
        }).delaySeconds()
    }

    func testMissingKeyIsOff() {
        XCTAssertNil(delay(nil))
    }

    func testZeroIsOff() {
        XCTAssertNil(delay(NSNumber(value: 0)))
    }

    func testNegativeIsOff() {
        XCTAssertNil(delay(NSNumber(value: -1)))
    }

    func testNumberIsTheDelay() {
        XCTAssertEqual(delay(NSNumber(value: 3600)), 3600)
    }

    func testNumberWrittenAsTextIsTheDelay() {
        XCTAssertEqual(delay("1800"), 1800)
    }

    func testOtherValuesAreOff() {
        XCTAssertNil(delay("soon"))
        XCTAssertNil(delay(["3600"]))
    }

    func testReport() {
        XCTAssertEqual(AutoLogoutReport.line(delaySeconds: 3600), "auto-logout=3600")
        XCTAssertEqual(AutoLogoutReport.line(delaySeconds: nil), "auto-logout=off")
    }
}

final class AutoLogoutNoticeTests: XCTestCase {
    func testOffShowsNothing() {
        XCTAssertNil(AutoLogoutNotice(mode: .off, delaySeconds: 3600, timerSeconds: nil))
    }

    func testBothModesWarn() {
        XCTAssertEqual(AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: nil)?.delaySeconds, 3600)
        XCTAssertEqual(AutoLogoutNotice(mode: .lidClosed, delaySeconds: 3600, timerSeconds: nil)?.delaySeconds, 3600)
    }

    func testSettingOffShowsNothing() {
        XCTAssertNil(AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: nil, timerSeconds: nil))
        XCTAssertNil(AutoLogoutNotice(mode: .lidClosed, delaySeconds: nil, timerSeconds: 7200))
    }

    func testShorterTimerEndsTheModeFirst() {
        XCTAssertNil(AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: 1800))
        XCTAssertNil(AutoLogoutNotice(mode: .lidClosed, delaySeconds: 3600, timerSeconds: 1800))
    }

    func testTimerEqualToTheDelayEndsTheModeFirst() {
        XCTAssertNil(AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: 3600))
    }

    func testLongerTimerStillWarns() {
        XCTAssertNotNil(AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: 7200))
        XCTAssertNotNil(AutoLogoutNotice(mode: .lidClosed, delaySeconds: 3600, timerSeconds: 7200))
    }

    func testTextNamesTheDelay() {
        let notice = AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: nil)
        XCTAssertEqual(notice?.title, "macOS will log you out")
        XCTAssertEqual(
            notice?.text,
            "Automatic logout after 1 h of inactivity is on. The mode ends when macOS logs you out. Change it in System Settings > Privacy & Security."
        )
        XCTAssertEqual(
            AutoLogoutNotice(mode: .lidClosed, delaySeconds: 1800, timerSeconds: nil)?.text,
            "Automatic logout after 30 min of inactivity is on. The mode ends when macOS logs you out. Change it in System Settings > Privacy & Security."
        )
    }

    func testMessageStandsBelowTheModeAndAboveTheUpdate() {
        let messages = WindowMessage.list(
            helper: .approval,
            mode: .turnedOff("The timer ran out."),
            autoLogout: AutoLogoutNotice(mode: .lidClosed, delaySeconds: 3600, timerSeconds: nil),
            update: UpdateNotice(latest: "1.1.0", current: "1.0.0")
        )
        XCTAssertEqual(messages.map(\.source), [.helper, .mode, .autoLogout, .update])
        let warning = messages[2]
        XCTAssertEqual(warning.kind, .info)
        XCTAssertEqual(warning.title, "macOS will log you out")
        XCTAssertEqual(warning.actionTitle, "Open System Settings")
        XCTAssertNil(warning.action)
    }

    func testMessageAlone() {
        let messages = WindowMessage.list(
            helper: nil,
            mode: nil,
            autoLogout: AutoLogoutNotice(mode: .keepScreenOn, delaySeconds: 3600, timerSeconds: nil)
        )
        XCTAssertEqual(messages.map(\.source), [.autoLogout])
    }
}

@MainActor
final class AutoLogoutMonitorTests: XCTestCase {
    private final class Source: AutoLogoutSource {
        var delay: Int?
        var reads = 0

        init(delay: Int?) {
            self.delay = delay
        }

        func delaySeconds() -> Int? {
            reads += 1
            return delay
        }
    }

    func testRefreshReadsTheSettingAgain() {
        let source = Source(delay: 3600)
        let monitor = AutoLogoutMonitor(source: source)
        XCTAssertEqual(monitor.delaySeconds, 3600)
        XCTAssertNotNil(monitor.notice(mode: .keepScreenOn, timerSeconds: nil))

        source.delay = nil
        monitor.refresh()
        XCTAssertEqual(source.reads, 2)
        XCTAssertNil(monitor.delaySeconds)
        XCTAssertNil(monitor.notice(mode: .keepScreenOn, timerSeconds: nil))
    }
}
