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

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBorder = Color(nsColor: .tertiaryLabelColor)
    static let valueBackground = Color(nsColor: .quaternaryLabelColor)

    private static let blueAccent = dynamic(AccentTheme.blue.color)
    private static let amberAccent = dynamic(AccentTheme.amber.color)

    private static func dynamic(_ rgb: ThemedRGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            return color(rgb.value(isDark: match == .darkAqua || match == .vibrantDark))
        })
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
