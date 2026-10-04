import Combine
import Foundation

/// An sRGB color as 0xRRGGBB for the light and the dark appearance.
public struct ThemedRGB: Equatable {
    public let light: UInt32
    public let dark: UInt32

    public func value(isDark: Bool) -> UInt32 {
        isDark ? dark : light
    }
}

public enum AccentTheme: String, CaseIterable {
    case blue
    case amber

    public var color: ThemedRGB {
        switch self {
        case .blue: return ThemedRGB(light: 0x0B63E5, dark: 0x5B9DFF)
        case .amber: return ThemedRGB(light: 0xD98200, dark: 0xF5A623)
        }
    }

    /// The symbol drawn on an accent-colored background, the same for every accent.
    public static let onAccent = ThemedRGB(light: 0xFFFFFF, dark: 0x17181B)
}

/// Kept apart from `SafetyPreferences`: the accent is never sent to the helper.
@MainActor
public final class AccentPreference: ObservableObject {
    public static let key = "accentTheme"

    @Published public var theme: AccentTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.key) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Self.key).flatMap(AccentTheme.init(rawValue:)) ?? .blue
    }
}
