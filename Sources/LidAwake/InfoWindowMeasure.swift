import AppKit
import LidAwakeCore
import SwiftUI

extension InfoWindowController {
    static func whatsNew(updates: UpdateChecker, accent: AccentPreference, choice: WhatsNewChoice) -> InfoWindowController {
        InfoWindowController(
            title: String(localized: "What's new in \(Edition.name)"),
            changes: updates.objectWillChange.map { _ in }.eraseToAnyPublisher()
        ) { close in
            WhatsNewScreen(updates: updates, accent: accent, choice: choice, close: close)
        }
    }

    static func help(accent: AccentPreference) -> InfoWindowController {
        InfoWindowController(title: String(localized: "How to use LidAwake")) { close in
            HelpScreen(accent: accent, close: close)
        }
    }
}

/// `--measure-info-windows`: opens What's new and How to use LidAwake on screen as the menu
/// opens them, once as tall as the screen allows and once on a short screen, so the middle
/// scrolls, and prints where the title and the button are in each window, then quits.
enum InfoWindowMeasure {
    static let flag = "--measure-info-windows"
    /// The visible height of a screen short enough for both pages to scroll.
    static let shortScreen: CGFloat = 480

    @MainActor
    static func run() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let accent = AccentPreference(systemColorsChanged: NSColor.systemColorsDidChangeNotification)
        let choice = WhatsNewChoice()
        choice.recent()
        print("language: \(Bundle.main.preferredLocalizations.first ?? "?")")
        var failed = false
        for name in ["whats-new", "how-to-use"] {
            for visibleHeight in [nil, shortScreen] {
                // Never started, so it checks for nothing; a change is sent by hand, as when a
                // check ends while the window is open.
                let updates = UpdateChecker(source: UpdateBuild.source())
                let controller: InfoWindowController = name == "whats-new"
                    ? .whatsNew(updates: updates, accent: accent, choice: choice)
                    : .help(accent: accent)
                let screen = visibleHeight.map { "short screen \(Int($0))" } ?? "this screen"
                let steps: [(String, () -> Void)] = [
                    ("opened", { controller.show(visibleHeight: visibleHeight) }),
                    ("after a change", { updates.objectWillChange.send() }),
                    ("opened again", {
                        controller.close()
                        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
                        controller.show(visibleHeight: visibleHeight)
                    }),
                ]
                for (step, action) in steps where name == "whats-new" || step != "after a change" {
                    action()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
                    if let line = report(controller) {
                        print("\(name), \(screen), \(step): \(line)")
                    } else {
                        print("\(name), \(screen), \(step): not measured")
                        failed = true
                    }
                }
                controller.close()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            }
        }
        return failed ? 1 : 0
    }

    @MainActor
    private static func report(_ controller: InfoWindowController) -> String? {
        guard let measured = controller.measured,
              let host = measured.window.contentView,
              let page = measured.marks[.page],
              let title = measured.marks[.title],
              let button = measured.marks[.button]
        else { return nil }
        let window = measured.window
        let titleBar = window.frame.height - window.contentLayoutRect.height
        let top = title.minY
        let bottom = host.bounds.height - button.maxY
        let capsTop = top + InfoPage<EmptyView, EmptyView, EmptyView>.titleInset
        return [
            "window \(f(window.frame.height))",
            "content view \(f(host.bounds.height))",
            "title bar \(f(titleBar))",
            "safe area top \(f(host.safeAreaInsets.top))",
            "page \(f(page.minY))...\(f(page.maxY))",
            "scroll \(measured.scrollHeight.map(f) ?? "none")",
            "title top \(f(top)) (capitals \(f(capsTop)))",
            "under button \(f(bottom))",
            "difference \(f(bottom - capsTop))",
        ].joined(separator: ", ")
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
