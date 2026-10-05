import Foundation

/// `--log-window-geometry`: the app runs as usual and prints the window geometry each time the
/// window opens or changes height.
enum WindowGeometryLog {
    static let flag = "--log-window-geometry"
    static let isEnabled = CommandLine.arguments.contains(flag)
}
