import XCTest
import LidAwakeShared

final class ScheduledWakeTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    func testStatusField() {
        XCTAssertEqual(ScheduledWake.statusField([], timeZone: berlin), "wake=off")
        XCTAssertEqual(ScheduledWake.statusField(nil, timeZone: berlin), "wake=unknown")
        let wakes = [
            Date(timeIntervalSince1970: 1_791_957_600), // 2026-10-14 06:00 UTC
            Date(timeIntervalSince1970: 1_791_871_200), // 2026-10-13 06:00 UTC
        ]
        XCTAssertEqual(
            ScheduledWake.statusField(wakes, timeZone: berlin),
            "wake=2026-10-13T08:00,2026-10-14T08:00"
        )
    }

    func testParsesTimeOfDay() {
        XCTAssertEqual(ScheduledWake.minuteOfDay(from: "08:00"), 480)
        XCTAssertEqual(ScheduledWake.minuteOfDay(from: "00:00"), 0)
        XCTAssertEqual(ScheduledWake.minuteOfDay(from: "23:59"), 1439)
        XCTAssertEqual(ScheduledWake.minuteOfDay(from: "off"), ScheduledWake.off)
        for text in ["24:00", "8:5", "8:05", "", "12:60", "08:00:00", " 08:00", "0800", "OFF", "٠٨:٠٠"] {
            XCTAssertNil(ScheduledWake.minuteOfDay(from: text), text)
        }
    }

    func testWireRoundTrip() {
        let wakes = [Date(timeIntervalSince1970: 1_791_957_600), Date(timeIntervalSince1970: 1_791_871_200)]
        let text = ScheduledWakeWire.encode(wakes)
        XCTAssertEqual(text, "1791871200\n1791957600")
        XCTAssertEqual(ScheduledWakeWire.decode(text), wakes.sorted())
        XCTAssertEqual(ScheduledWakeWire.encode([]), "")
        XCTAssertEqual(ScheduledWakeWire.decode(""), [])
        XCTAssertNil(ScheduledWakeWire.decode("1791871200\nsoon"))
        XCTAssertNil(ScheduledWakeWire.decode("1791871200\n"))
    }
}
