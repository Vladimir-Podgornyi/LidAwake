import AppKit
import LidAwakeCore
import SwiftUI

enum Palette {
    static func accent(_ theme: AccentTheme) -> Color {
        switch theme {
        case .blue: return blueAccent
        case .amber: return amberAccent
        }
    }

    /// The checkmark drawn on an accent-colored badge.
    static let onAccent = dynamic(AccentTheme.onAccent)

    static func cardBackground(_ look: WindowLook) -> Color {
        look.hasTranslucentCards ? glassCardFill : opaqueCardBackground
    }

    /// The border of a card that is not selected, and of the neutral banner.
    static func cardBorder(_ look: WindowLook) -> Color {
        look.hasTranslucentCards ? glassCardBorder : opaqueCardBorder
    }

    static let solidWindowBackground = Color(nsColor: .windowBackgroundColor)
    static let valueBackground = Color(nsColor: .quaternaryLabelColor)

    private static let blueAccent = dynamic(AccentTheme.blue.color)
    private static let amberAccent = dynamic(AccentTheme.amber.color)
    private static let opaqueCardBackground = Color(nsColor: .controlBackgroundColor)
    private static let opaqueCardBorder = Color(nsColor: .tertiaryLabelColor)
    private static let glassCardFill = dynamic(GlassCard.fill)
    private static let glassCardBorder = dynamic(GlassCard.border)

    private static func dynamic(_ rgb: ThemedRGB) -> Color {
        dynamic { color(rgb.value(isDark: $0)) }
    }

    private static func dynamic(_ tint: ThemedTint) -> Color {
        dynamic { isDark in
            let value = tint.value(isDark: isDark)
            return color(value.rgb, alpha: value.opacity)
        }
    }

    private static func dynamic(_ make: @escaping (_ isDark: Bool) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            return make(match == .darkAqua || match == .vibrantDark)
        })
    }

    private static func color(_ rgb: UInt32, alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
