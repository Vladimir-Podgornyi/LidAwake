import CoreGraphics

/// Keeps the window within the screen: the header and the mode cards stay put, the part below
/// them scrolls when the whole does not fit.
public enum WindowHeightLimit {
    /// Left free between the bottom of the window and the bottom of the visible screen area,
    /// which also covers the gap between the menu bar and the window.
    public static let screenMargin: CGFloat = 16
    /// The scrolling part never gets shorter than this, even on a very small screen.
    public static let minimumScrollHeight: CGFloat = 120

    /// The tallest the window may be on a screen whose visible area, without the menu bar
    /// and the Dock, is `visibleScreenHeight` high.
    public static func maxWindowHeight(visibleScreenHeight: CGFloat) -> CGFloat {
        max(0, visibleScreenHeight - screenMargin)
    }

    /// The height of the scrolling part, or nil when everything fits and nothing scrolls.
    /// `fixedHeight` is the part that stays put, `contentHeight` the full height of the rest.
    public static func scrollHeight(fixedHeight: CGFloat, contentHeight: CGFloat, maxWindowHeight: CGFloat?) -> CGFloat? {
        guard let maxWindowHeight, fixedHeight + contentHeight > maxWindowHeight else { return nil }
        return max(minimumScrollHeight, maxWindowHeight - fixedHeight)
    }
}
