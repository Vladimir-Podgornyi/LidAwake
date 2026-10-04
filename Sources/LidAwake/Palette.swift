import AppKit
import SwiftUI

enum Palette {
    static let accent = dynamic(light: 0x0B63E5, dark: 0x5B9DFF)
    /// The checkmark drawn on an accent-colored badge.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x17181B)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBorder = Color(nsColor: .tertiaryLabelColor)
    static let valueBackground = Color(nsColor: .quaternaryLabelColor)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            return color(match == .darkAqua || match == .vibrantDark ? dark : light)
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
