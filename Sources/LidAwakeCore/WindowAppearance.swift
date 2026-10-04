import Combine
import Foundation

/// The Appearance choice. It only applies on macOS 26 and later.
public enum WindowAppearance: String, CaseIterable {
    case glass
    case solid
}

/// How the window is actually drawn.
public enum WindowLook: Equatable {
    /// macOS 13–15: system background, opaque cards.
    case standard
    /// System material, translucent cards.
    case glass
    /// Glass with Reduce Transparency on: system background, opaque cards.
    case glassOpaqueCards
    /// Own opaque background, opaque cards.
    case solid

    public init(style: WindowAppearance, isSystem26OrLater: Bool, reduceTransparency: Bool) {
        guard isSystem26OrLater else {
            self = .standard
            return
        }
        switch style {
        case .glass: self = reduceTransparency ? .glassOpaqueCards : .glass
        case .solid: self = .solid
        }
    }

    public var drawsOwnBackground: Bool {
        self == .solid
    }

    public var hasTranslucentCards: Bool {
        self == .glass
    }

    public static var isSystem26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    /// The Appearance row is shown only where the choice has an effect.
    public static func showsStyleSetting(isSystem26OrLater: Bool) -> Bool {
        isSystem26OrLater
    }
}

/// An sRGB color with opacity for the light and the dark appearance.
public struct ThemedTint: Equatable {
    public struct Tint: Equatable {
        public let rgb: UInt32
        public let opacity: Double
    }

    public let light: Tint
    public let dark: Tint

    public func value(isDark: Bool) -> Tint {
        isDark ? dark : light
    }
}

/// Fill and border of cards and the neutral banner in the glass look.
public enum GlassCard {
    public static let fill = ThemedTint(
        light: .init(rgb: 0xFFFFFF, opacity: 0.50),
        dark: .init(rgb: 0xFFFFFF, opacity: 0.07)
    )
    /// The border of a card that is not selected; a selected card uses the accent.
    public static let border = ThemedTint(
        light: .init(rgb: 0x000000, opacity: 0.10),
        dark: .init(rgb: 0xFFFFFF, opacity: 0.14)
    )
}

/// Kept apart from `SafetyPreferences`: the window style is never sent to the helper.
@MainActor
public final class WindowAppearancePreference: ObservableObject {
    public static let key = "windowStyle"

    @Published public var style: WindowAppearance {
        didSet { defaults.set(style.rawValue, forKey: Self.key) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Self.key).flatMap(WindowAppearance.init(rawValue:)) ?? .glass
    }
}
