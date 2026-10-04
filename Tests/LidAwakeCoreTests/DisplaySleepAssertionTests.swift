import Foundation
import IOKit.pwr_mgt
import XCTest
@testable import LidAwakeCore

final class DisplaySleepAssertionTests: XCTestCase {
    func testAssertionAppearsInProcessAssertions() throws {
        let name = "LidAwake test \(UUID().uuidString)"
        let assertion = DisplaySleepAssertion(name: name)

        try assertion.acquire()
        XCTAssertTrue(currentProcessHasAssertion(named: name))

        assertion.release()
        XCTAssertFalse(currentProcessHasAssertion(named: name))
    }

    private func currentProcessHasAssertion(named name: String) -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let mine = all[NSNumber(value: getpid())]
        else { return false }
        return mine.contains { entry in
            entry[kIOPMAssertionNameKey] as? String == name
                && entry[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep
        }
    }
}
