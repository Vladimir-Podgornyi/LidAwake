import XCTest
@testable import LidAwakeShared

final class IdleEventWireTests: XCTestCase {
    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    func testEventsSurviveTheTrip() {
        let events = [
            IdleEvent(time: at(0.25), cause: .app("Example App")),
            IdleEvent(time: at(60), cause: .input),
            IdleEvent(time: at(120), cause: .load(busiest: "example-tool")),
            IdleEvent(time: at(180), cause: .load(busiest: nil)),
            IdleEvent(time: at(240), cause: .idle(minutes: 20)),
        ]
        XCTAssertEqual(IdleEventWire.decode(IdleEventWire.encode(events)), events)
        XCTAssertEqual(IdleEventWire.decode(IdleEventWire.encode([])), [])
    }

    func testWatchedAppEventSurvivesTheTrip() {
        let events = [IdleEvent(time: at(30), cause: .watched("Code Editor"))]
        XCTAssertEqual(IdleEventWire.encode(events), "1800000030.0\twatched\tCode Editor")
        XCTAssertEqual(IdleEventWire.decode(IdleEventWire.encode(events)), events)
    }

    func testSeparatorsInNamesBecomeSpaces() {
        let events = [IdleEvent(time: at(0), cause: .app("odd\tname\nhere\r"))]
        XCTAssertEqual(IdleEventWire.decode(IdleEventWire.encode(events)), [
            IdleEvent(time: at(0), cause: .app("odd name here ")),
        ])
    }

    func testLinesItDoesNotKnowAreSkipped() {
        let text = [
            "1800000000.0\tinput",
            "1800000060.0\tsomething-new\tvalue",
            "not a time\tinput",
            "1800000120.0\tidle\tmany",
            "1800000180.0\tidle\t10",
        ].joined(separator: "\n")
        XCTAssertEqual(IdleEventWire.decode(text), [
            IdleEvent(time: at(0), cause: .input),
            IdleEvent(time: at(180), cause: .idle(minutes: 10)),
        ])
    }
}
