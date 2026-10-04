import AppKit
import LidAwakeCore
import SwiftUI

/// The mode shapes, drawn on a 24 × 24 grid with y pointing down.
enum ModeIcon {
    struct Glyph {
        let filled: CGPath
        let stroked: CGPath
    }

    static let gridSize: CGFloat = 24
    static let strokeStyle = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

    static func glyph(for mode: Mode) -> Glyph {
        switch mode {
        case .off: return Glyph(filled: CGMutablePath(), stroked: combined(screen, stand))
        case .keepScreenOn: return Glyph(filled: screen, stroked: combined(screen, stand))
        case .lidClosed: return Glyph(filled: closedLid, stroked: combined(closedLid, rays))
        }
    }

    /// A template image for the menu bar; the system picks its color.
    static func menuBarImage(for mode: Mode) -> NSImage {
        menuBarImages[mode] ?? NSImage()
    }

    private static let menuBarImages = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, image(for: $0, size: 18)) })

    private static func image(for mode: Mode, size: CGFloat) -> NSImage {
        let glyph = glyph(for: mode)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / gridSize, y: rect.height / gridSize)
            context.setFillColor(.black)
            context.addPath(glyph.filled)
            context.fillPath()
            context.setStrokeColor(.black)
            context.setLineWidth(strokeStyle.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(glyph.stroked)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LidAwake"
        return image
    }

    private static let screen = CGPath(
        roundedRect: CGRect(x: 5, y: 5.5, width: 14, height: 9.5),
        cornerWidth: 1.6,
        cornerHeight: 1.6,
        transform: nil
    )

    private static let stand = lines([(CGPoint(x: 2.5, y: 18.5), CGPoint(x: 21.5, y: 18.5))])

    private static let closedLid = CGPath(
        roundedRect: CGRect(x: 2.5, y: 13.5, width: 19, height: 5),
        cornerWidth: 2.5,
        cornerHeight: 2.5,
        transform: nil
    )

    private static let rays = lines([
        (CGPoint(x: 12, y: 5.5), CGPoint(x: 12, y: 8.5)),
        (CGPoint(x: 6.8, y: 7.2), CGPoint(x: 8.4, y: 9.6)),
        (CGPoint(x: 17.2, y: 7.2), CGPoint(x: 15.6, y: 9.6)),
    ])

    private static func lines(_ segments: [(CGPoint, CGPoint)]) -> CGPath {
        let path = CGMutablePath()
        for (start, end) in segments {
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }

    private static func combined(_ paths: CGPath...) -> CGPath {
        let path = CGMutablePath()
        paths.forEach { path.addPath($0) }
        return path
    }
}

/// The mode shape in the current foreground style.
struct ModeIconView: View {
    let mode: Mode

    var body: some View {
        Canvas { context, size in
            let glyph = ModeIcon.glyph(for: mode)
            context.scaleBy(x: size.width / ModeIcon.gridSize, y: size.height / ModeIcon.gridSize)
            context.fill(Path(glyph.filled), with: .foreground)
            context.stroke(Path(glyph.stroked), with: .foreground, style: ModeIcon.strokeStyle)
        }
        .accessibilityHidden(true)
    }
}

struct MenuBarIcon: View {
    @ObservedObject var controller: ModeController

    var body: some View {
        Image(nsImage: ModeIcon.menuBarImage(for: controller.mode))
            .accessibilityLabel(Text(verbatim: "LidAwake"))
    }
}
