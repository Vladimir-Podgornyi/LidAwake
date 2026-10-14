import AppKit
import LidAwakeCore
import SwiftUI

enum Palette {
    static func accent(_ theme: AccentTheme) -> Color {
        switch theme {
        case .blue: return blueAccent
        case .system: return dynamic(systemAccent())
        case .amber: return amberAccent
        }
    }

    /// The checkmark drawn on an accent-colored badge.
    static func onAccent(_ theme: AccentTheme) -> Color {
        guard theme == .system else { return fixedOnAccent }
        let accent = systemAccent()
        return dynamic(ThemedRGB(
            light: AccentTheme.onSystemAccent(accent.light, isDark: false),
            dark: AccentTheme.onSystemAccent(accent.dark, isDark: true)
        ))
    }

    static func cardBackground(_ look: WindowLook) -> Color {
        look.hasTranslucentCards ? glassCardFill : opaqueCardBackground
    }

    /// The border of a card that is not selected, and of the neutral banner.
    static func cardBorder(_ look: WindowLook) -> Color {
        look.hasTranslucentCards ? glassCardBorder : opaqueCardBorder
    }

    static let solidWindowBackground = Color(nsColor: .windowBackgroundColor)
    static let valueBackground = Color(nsColor: .quaternaryLabelColor)
    /// The track of a switch that is off, as in the mockup.
    static let switchOff = dynamic { color($0 ? 0x6E717A : 0x8E9197) }

    private static let blueAccent = dynamic(AccentTheme.blue.color!)
    private static let amberAccent = dynamic(AccentTheme.amber.color!)
    private static let fixedOnAccent = dynamic(AccentTheme.onAccent)
    private static let opaqueCardBackground = Color(nsColor: .controlBackgroundColor)
    private static let opaqueCardBorder = Color(nsColor: .tertiaryLabelColor)
    private static let glassCardFill = dynamic(GlassCard.fill)
    private static let glassCardBorder = dynamic(GlassCard.border)

    /// Read anew on every call: the system color keeps its name when the accent changes in the
    /// macOS settings, so a view drawn with it would compare equal and keep the old color.
    /// With Multicolor chosen, macOS gives its blue, as the app sets no accent of its own.
    private static func systemAccent() -> ThemedRGB {
        ThemedRGB(light: rgb(.controlAccentColor, in: .aqua), dark: rgb(.controlAccentColor, in: .darkAqua))
    }

    private static func rgb(_ color: NSColor, in name: NSAppearance.Name) -> UInt32 {
        var result: UInt32 = 0
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            func byte(_ component: CGFloat) -> UInt32 {
                UInt32((min(max(component, 0), 1) * 255).rounded())
            }
            result = byte(srgb.redComponent) << 16 | byte(srgb.greenComponent) << 8 | byte(srgb.blueComponent)
        }
        return result
    }

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
