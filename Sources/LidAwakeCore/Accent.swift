import Combine
import Foundation

/// An sRGB color as 0xRRGGBB for the light and the dark appearance.
public struct ThemedRGB: Equatable {
    public let light: UInt32
    public let dark: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    public func value(isDark: Bool) -> UInt32 {
        isDark ? dark : light
    }
}

public enum AccentTheme: String, CaseIterable {
    case blue
    case system
    case amber

    /// nil for `system`, which takes the accent color chosen in the macOS settings.
    public var color: ThemedRGB? {
        switch self {
        case .blue: return ThemedRGB(light: 0x0B63E5, dark: 0x5B9DFF)
        case .system: return nil
        case .amber: return ThemedRGB(light: 0xD98200, dark: 0xF5A623)
        }
    }

    /// The symbol drawn on an accent-colored background, the same for Blue and Amber.
    public static let onAccent = ThemedRGB(light: 0xFFFFFF, dark: 0x17181B)

    /// The symbol on the accent chosen in the macOS settings: the usual one for the appearance,
    /// or the other one where the usual one falls below 3:1, the least contrast for a symbol.
    public static func onSystemAccent(_ accent: UInt32, isDark: Bool) -> UInt32 {
        let usual = onAccent.value(isDark: isDark)
        guard Contrast.ratio(usual, accent) < 3 else { return usual }
        let other = onAccent.value(isDark: !isDark)
        return Contrast.ratio(other, accent) > Contrast.ratio(usual, accent) ? other : usual
    }
}

/// WCAG 2 contrast of sRGB colors given as 0xRRGGBB.
public enum Contrast {
    public static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }
}

/// Kept apart from `SafetyPreferences`: the accent is never sent to the helper.
@MainActor
public final class AccentPreference: ObservableObject {
    public static let key = "accentTheme"

    @Published public var theme: AccentTheme {
        didSet { defaults.set(theme.rawValue, forKey: Self.key) }
    }

    private let defaults: UserDefaults
    private var systemColorsObserver: AnyCancellable?

    /// `systemColorsChanged` is the notification posted when the accent changes in the macOS
    /// settings; with the `system` accent it redraws the views that show the accent.
    public init(
        defaults: UserDefaults = .standard,
        systemColorsChanged: Notification.Name? = nil,
        center: NotificationCenter = .default
    ) {
        self.defaults = defaults
        theme = defaults.string(forKey: Self.key).flatMap(AccentTheme.init(rawValue:)) ?? .system
        if let systemColorsChanged {
            systemColorsObserver = center.publisher(for: systemColorsChanged)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.systemColorsDidChange() }
                }
        }
    }

    private func systemColorsDidChange() {
        guard theme == .system else { return }
        objectWillChange.send()
    }
}
