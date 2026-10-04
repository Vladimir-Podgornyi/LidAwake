import Foundation

public protocol ScreenLocking: AnyObject {
    var isAvailable: Bool { get }
    func lock()
}

/// macOS has no public call that locks the screen right away, so this uses
/// SACLockScreenImmediate from the private login framework.
public final class LoginScreenLocker: ScreenLocking {
    private typealias LockFunction = @convention(c) () -> Int32

    private static let lockFunction: LockFunction? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            return nil
        }
        return unsafeBitCast(symbol, to: LockFunction.self)
    }()

    public init() {}

    public var isAvailable: Bool {
        Self.lockFunction != nil
    }

    public func lock() {
        _ = Self.lockFunction?()
    }
}
