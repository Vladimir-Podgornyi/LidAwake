import CoreGraphics
import Foundation

/// Where the window stands, in screen coordinates (origin at the bottom left).
public struct WindowGeometry: Equatable {
    /// The screen without the menu bar and the Dock.
    public let visibleFrame: CGRect
    /// The window's frame on the screen.
    public let windowFrame: CGRect
    /// The height of the window's content view.
    public let contentHeight: CGFloat

    public init(visibleFrame: CGRect, windowFrame: CGRect, contentHeight: CGFloat) {
        self.visibleFrame = visibleFrame
        self.windowFrame = windowFrame
        self.contentHeight = contentHeight
    }

    /// What the window adds around its content.
    public var chromeHeight: CGFloat {
        max(0, windowFrame.height - contentHeight)
    }

    /// From the bottom of the window to the bottom of the visible area; negative when the
    /// window reaches below it.
    public var bottomGap: CGFloat {
        windowFrame.minY - visibleFrame.minY
    }
}

/// Keeps the window within the screen: the header and the mode cards stay put, the part below
/// them scrolls when the whole does not fit.
public enum WindowHeightLimit {
    /// Kept free between the bottom of the window and the bottom of the visible area.
    public static let bottomMargin: CGFloat = 12
    /// The scrolling part never gets shorter than this, even on a very small screen.
    public static let minimumScrollHeight: CGFloat = 120

    /// The tallest the content may be with the window's top where it is now.
    public static func maxContentHeight(_ geometry: WindowGeometry) -> CGFloat {
        let lowestBottom = geometry.visibleFrame.minY + bottomMargin
        return max(0, geometry.windowFrame.maxY - geometry.chromeHeight - lowestBottom)
    }

    /// The height of the scrolling part, or nil when everything fits and nothing scrolls.
    /// `fixedHeight` is the part that stays put, `contentHeight` the full height of the rest.
    public static func scrollHeight(fixedHeight: CGFloat, contentHeight: CGFloat, maxHeight: CGFloat?) -> CGFloat? {
        guard let maxHeight, fixedHeight + contentHeight > maxHeight else { return nil }
        return max(minimumScrollHeight, maxHeight - fixedHeight)
    }
}

/// Turns the window's real geometry into the content limit. If the window, already laid out
/// within the limit, still reaches below the margin, the limit is lowered by the missing part
/// and stays lower until the screen changes.
public struct WindowFit: Equatable {
    /// How far the geometry turned out to be wrong; never more than this.
    public static let maxCorrection: CGFloat = 200

    public private(set) var correction: CGFloat = 0
    public private(set) var limit: CGFloat?

    public init() {}

    @discardableResult
    public mutating func update(_ geometry: WindowGeometry) -> CGFloat {
        let laidOutWithinLimit = limit.map { geometry.contentHeight <= $0 + 0.5 } ?? false
        let missing = WindowHeightLimit.bottomMargin - geometry.bottomGap
        if laidOutWithinLimit, missing > 0.5 {
            correction = min(Self.maxCorrection, correction + missing)
        }
        let value = max(0, WindowHeightLimit.maxContentHeight(geometry) - correction)
        limit = value
        return value
    }

    /// The window moved to another screen or the screen changed: start from the geometry again.
    public mutating func reset() {
        correction = 0
        limit = nil
    }
}

/// The `--log-window-geometry` line.
public enum WindowGeometryReport {
    public static func line(_ geometry: WindowGeometry, limit: CGFloat, isScrolling: Bool) -> String {
        [
            "visible=\(rect(geometry.visibleFrame))",
            "frame=\(rect(geometry.windowFrame))",
            "content-height=\(number(geometry.contentHeight))",
            "limit=\(number(limit))",
            "scrolls=\(isScrolling ? "yes" : "no")",
            "bottom-gap=\(number(geometry.bottomGap))",
        ].joined(separator: " ")
    }

    private static func rect(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map(number).joined(separator: ",")
    }

    private static func number(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", Double(rounded))
    }
}
