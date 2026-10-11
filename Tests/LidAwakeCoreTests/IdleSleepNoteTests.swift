import LidAwakeShared
import XCTest
@testable import LidAwakeCore

final class IdleSleepNoteTests: XCTestCase {
    private let plain = IdleSleepNote(text: "After the work is done", dot: nil)

    private func status(_ state: IdleState, counted: Int = 0, holders: [String]? = []) -> IdleStatus {
        IdleStatus(
            state: state,
            countedMinutes: counted,
            requiredMinutes: state == .off ? 0 : 20,
            cores: 0.2,
            inputIdleSeconds: 600,
            holders: holders
        )
    }

    private func note(
        mode: Mode = .lidClosed,
        isEnabled: Bool = true,
        isPaused: Bool = false,
        _ status: IdleStatus?
    ) -> IdleSleepNote {
        IdleSleepNote.make(mode: mode, isEnabled: isEnabled, isPaused: isPaused, status: status)
    }

    // MARK: What the helper sees

    func testAProgramKeepsTheMacAwake() {
        XCTAssertEqual(
            note(status(.busyApp, holders: ["Example App"])),
            IdleSleepNote(text: "Kept awake by Example App", dot: .busy)
        )
    }

    func testTheLoadKeepsTheMacAwake() {
        XCTAssertEqual(note(status(.busyCPU)), IdleSleepNote(text: "Kept awake by CPU load", dot: .busy))
    }

    func testInputKeepsTheMacAwake() {
        XCTAssertEqual(note(status(.busyInput)), IdleSleepNote(text: "Kept awake by keyboard or mouse", dot: .busy))
    }

    func testTheCount() {
        XCTAssertEqual(note(status(.counting, counted: 7)), IdleSleepNote(text: "Idle for 7 of 20 min", dot: .counting))
    }

    // MARK: The plain text

    func testOtherModesShowThePlainText() {
        for mode in [Mode.off, .keepScreenOn] {
            XCTAssertEqual(note(mode: mode, status(.counting, counted: 7)), plain, "\(mode)")
        }
    }

    func testTheSettingOffShowsThePlainText() {
        XCTAssertEqual(note(isEnabled: false, status(.busyCPU)), plain)
    }

    func testAPausedSessionShowsThePlainText() {
        XCTAssertEqual(note(isPaused: true, status(.counting, counted: 7)), plain)
    }

    func testNoStatusShowsThePlainText() {
        XCTAssertEqual(note(nil), plain)
    }

    func testTheHelperCountingNothingShowsThePlainText() {
        XCTAssertEqual(note(status(.off)), plain)
    }

    func testAProgramWithoutANameShowsThePlainText() {
        XCTAssertEqual(note(status(.busyApp, holders: [])), plain)
        XCTAssertEqual(note(status(.busyApp, holders: nil)), plain)
        XCTAssertEqual(note(status(.busyApp, holders: [" "])), plain)
    }

    // MARK: The program's name

    func testTheSameProgramsGiveTheSameNameInAnyOrder() {
        let names = ["Worker", "Example App", "Builder"]
        var seen = Set<String>()
        for order in [names, names.reversed(), [names[1], names[2], names[0]]] {
            seen.insert(note(status(.busyApp, holders: order)).text)
        }
        XCTAssertEqual(seen, ["Kept awake by Builder"])
    }

    func testALongNameIsCut() {
        let name = String(repeating: "a", count: 40)
        let shown = IdleSleepNote.appName([name])
        XCTAssertEqual(shown?.count, IdleSleepNote.longestAppName)
        XCTAssertEqual(shown?.hasSuffix("…"), true)
        let fits = String(repeating: "b", count: IdleSleepNote.longestAppName)
        XCTAssertEqual(IdleSleepNote.appName([fits]), fits)
    }

    // MARK: The menu

    func testTheMenuOffersFourValues() {
        XCTAssertEqual(MenuChoices.list(SafetyPreferences.idleSleepChoices, current: 20), [10, 20, 30, 60])
        XCTAssertEqual(SafetyPreferences.idleSleepChoices.map(DurationFormat.minutes), ["10 min", "20 min", "30 min", "60 min"])
    }

    func testAStoredValueOutsideTheListIsAdded() {
        XCTAssertEqual(MenuChoices.list(SafetyPreferences.idleSleepChoices, current: 3), [3, 10, 20, 30, 60])
        XCTAssertEqual(MenuChoices.list(SafetyPreferences.idleSleepChoices, current: 45), [10, 20, 30, 45, 60])
    }
}
