import CryptoKit
import Foundation
import LidAwakeShared

/// Remembers the digest of the helper plist the helper was last registered with.
public protocol HelperRegistrationStore: AnyObject {
    var registrationDigest: String? { get set }
}

public final class DefaultsRegistrationStore: HelperRegistrationStore {
    public static let key = "helperRegistrationDigest"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var registrationDigest: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

public enum HelperPlist {
    public static func url(inBundle bundleURL: URL) -> URL {
        bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons")
            .appendingPathComponent(HelperConstants.plistName)
    }

    public static func read(inBundle bundleURL: URL) -> Data? {
        try? Data(contentsOf: url(inBundle: bundleURL))
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
