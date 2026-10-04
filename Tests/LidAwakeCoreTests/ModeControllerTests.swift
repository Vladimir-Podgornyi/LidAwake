import XCTest
@testable import LidAwakeCore

private final class FakeAssertion: PowerAssertion {
    var shouldFail = false
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private(set) var isHeld = false

    func acquire() throws {
        acquireCount += 1
        if shouldFail {
            throw PowerAssertionError(code: -1)
        }
        isHeld = true
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}

final class ModeControllerTests: XCTestCase {
    func testStartsOff() {
        let assertion = FakeAssertion()
        let controller = ModeController(displayAssertion: assertion)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
    }

    func testKeepScreenOnAcquiresAndOffReleases() throws {
        let assertion = FakeAssertion()
        let controller = ModeController(displayAssertion: assertion)

        try controller.select(.keepScreenOn)
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertTrue(assertion.isHeld)

        try controller.select(.off)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
    }

    func testRepeatedKeepScreenOnCreatesOneAssertion() throws {
        let assertion = FakeAssertion()
        let controller = ModeController(displayAssertion: assertion)

        try controller.select(.keepScreenOn)
        try controller.select(.keepScreenOn)

        XCTAssertEqual(assertion.acquireCount, 1)
        XCTAssertEqual(controller.mode, .keepScreenOn)
    }

    func testAcquireFailureLeavesModeOff() {
        let assertion = FakeAssertion()
        assertion.shouldFail = true
        let controller = ModeController(displayAssertion: assertion)

        XCTAssertThrowsError(try controller.select(.keepScreenOn))
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(assertion.isHeld)
    }

    func testLidClosedIsRejectedFromOff() {
        let assertion = FakeAssertion()
        let controller = ModeController(displayAssertion: assertion)

        XCTAssertThrowsError(try controller.select(.lidClosed)) { error in
            XCTAssertEqual(error as? ModeError, .unavailable(.lidClosed))
        }
        XCTAssertEqual(controller.mode, .off)
        XCTAssertEqual(assertion.acquireCount, 0)
    }

    func testLidClosedIsRejectedFromKeepScreenOn() throws {
        let assertion = FakeAssertion()
        let controller = ModeController(displayAssertion: assertion)
        try controller.select(.keepScreenOn)

        XCTAssertThrowsError(try controller.select(.lidClosed))
        XCTAssertEqual(controller.mode, .keepScreenOn)
        XCTAssertTrue(assertion.isHeld)
        XCTAssertEqual(assertion.releaseCount, 0)
    }
}
