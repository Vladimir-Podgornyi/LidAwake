import XCTest
import LidAwakeShared

final class IdleStatusTests: XCTestCase {
    private func status(
        _ state: IdleState,
        counted: Int = 0,
        required: Int = 0,
        cores: Double? = nil,
        input: Double? = nil,
        holders: [String]? = nil
    ) -> IdleStatus {
        IdleStatus(
            state: state,
            countedMinutes: counted,
            requiredMinutes: required,
            cores: cores,
            inputIdleSeconds: input,
            holders: holders
        )
    }

    func testStateTokens() {
        XCTAssertEqual(status(.off).token, "off")
        XCTAssertEqual(status(.busyCPU).token, "busy-cpu")
        XCTAssertEqual(status(.busyApp).token, "busy-app")
        XCTAssertEqual(status(.busyInput).token, "busy-input")
        XCTAssertEqual(status(.counting, counted: 3, required: 20).token, "counting:3/20")
    }

    func testReadingTokens() {
        let known = status(.counting, cores: 0.683, input: 12.34, holders: ["one", "two late"])
        XCTAssertEqual(known.coresToken, "0.68")
        XCTAssertEqual(known.inputToken, "12.3")
        XCTAssertEqual(known.holdersToken, "\"one,two late\"")

        let unknown = status(.counting, cores: nil, input: nil, holders: nil)
        XCTAssertEqual(unknown.coresToken, "unreadable")
        XCTAssertEqual(unknown.inputToken, "unreadable")
        XCTAssertEqual(unknown.holdersToken, "unreadable")

        XCTAssertEqual(status(.counting, holders: []).holdersToken, "none")
    }

    func testWatchedToken() {
        XCTAssertEqual(status(.counting).watchedToken, "none")
        let watched = IdleStatus(
            state: .counting,
            countedMinutes: 0,
            requiredMinutes: 20,
            cores: nil,
            inputIdleSeconds: nil,
            holders: nil,
            watched: [
                WatchedAppState(name: "Code Editor", isBusy: true),
                WatchedAppState(name: "Console", isBusy: false),
            ]
        )
        XCTAssertEqual(watched.watchedToken, "\"Code Editor:busy,Console:idle\"")
    }

    func testWatchedAppsSurviveTheTrip() {
        let states = [
            WatchedAppState(name: "Code Editor", isBusy: true),
            WatchedAppState(name: "Console", isBusy: false),
        ]
        XCTAssertEqual(WatchedAppState.decode(WatchedAppState.encode(states)), states)
        XCTAssertEqual(WatchedAppState.decode(WatchedAppState.encode([])), [])
        XCTAssertEqual(WatchedAppState.decode("busy\tOne\nmaybe\tTwo\nidle\tThree"), [
            WatchedAppState(name: "One", isBusy: true),
            WatchedAppState(name: "Three", isBusy: false),
        ])
    }

    /// The helper sends the state as a number, so the values have to stay as they are.
    func testWireValues() {
        XCTAssertEqual(IdleState.off.rawValue, 0)
        XCTAssertEqual(IdleState.busyCPU.rawValue, 1)
        XCTAssertEqual(IdleState.busyApp.rawValue, 2)
        XCTAssertEqual(IdleState.busyInput.rawValue, 3)
        XCTAssertEqual(IdleState.counting.rawValue, 4)
        for value in 0...4 {
            XCTAssertNotNil(IdleState(rawValue: value), "\(value)")
        }
        XCTAssertNil(IdleState(rawValue: 5))
    }
}
