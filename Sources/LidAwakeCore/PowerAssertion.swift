import Foundation
import IOKit
import IOKit.pwr_mgt

public protocol PowerAssertion: AnyObject {
    var isHeld: Bool { get }
    func acquire() throws
    func release()
}

public struct PowerAssertionError: Error, Equatable {
    public let code: IOReturn
}

/// Prevents the display from sleeping due to user inactivity.
public final class DisplaySleepAssertion: PowerAssertion {
    public let name: String
    public private(set) var assertionID: IOPMAssertionID?

    public var isHeld: Bool { assertionID != nil }

    public init(name: String = "LidAwake: Keep Screen On") {
        self.name = name
    }

    deinit {
        release()
    }

    public func acquire() throws {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError(code: result)
        }
        assertionID = id
    }

    public func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}
