import AppKit

/// The window under the menu bar icon.
@MainActor
enum MenuBarWindow {
    /// Closes the window by clicking the app's own menu bar icon, as a person would. The menu bar
    /// extra then hides the window itself and knows it is closed, so the next click on the icon
    /// opens it again. Closing the window directly would leave the extra thinking it is open.
    /// `window` is the open menu bar window; it is closed directly only if the icon is not found.
    static func close(_ window: NSWindow) {
        guard window.isVisible else { return }
        if let button = statusButton() {
            button.performClick(nil)
        } else {
            window.close()
        }
    }

    /// The app has one menu bar icon.
    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = firstStatusButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func firstStatusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let button = firstStatusButton(in: subview) {
                return button
            }
        }
        return nil
    }
}
