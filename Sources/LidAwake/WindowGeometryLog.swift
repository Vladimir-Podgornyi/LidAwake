import Foundation

/// `--log-window-geometry`: the app runs as usual and prints the geometry of the menu bar window,
/// What's new and How to use LidAwake each time one opens or changes height.
enum WindowGeometryLog {
    static let flag = "--log-window-geometry"
    static let isEnabled = CommandLine.arguments.contains(flag)
}

/// `--without-pro-offer`: the app runs as usual, but What's new leaves the Pro block out, as
/// LidAwake Pro and Intel Macs show it.
enum WithoutProOffer {
    static let flag = "--without-pro-offer"
    static let isEnabled = CommandLine.arguments.contains(flag)
}
