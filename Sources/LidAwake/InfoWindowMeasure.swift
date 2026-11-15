import AppKit
import LidAwakeCore
import SwiftUI

extension InfoWindowController {
    static func whatsNew(
        updates: UpdateChecker,
        accent: AccentPreference,
        choice: WhatsNewChoice,
        showsPro: Bool = Edition.showsProOffer
    ) -> InfoWindowController {
        InfoWindowController(
            title: String(localized: "What's new in \(Edition.name)"),
            changes: updates.objectWillChange.map { _ in }.eraseToAnyPublisher()
        ) { close in
            WhatsNewScreen(updates: updates, accent: accent, choice: choice, showsPro: showsPro, close: close)
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
/// scrolls, and prints where the title and the button are in each window, then quits. What's new
/// is opened with the Pro block and without it, as LidAwake Pro and Intel Macs show it. The windows
/// open in a SwiftUI app with its own run loop, as in the real app, so they become key.
enum InfoWindowMeasure {
    static let flag = "--measure-info-windows"
    /// The visible height of a screen short enough for both pages to scroll.
    static let shortScreen: CGFloat = 480

    @MainActor
    static func run() async -> Int32 {
        let accent = AccentPreference(systemColorsChanged: NSColor.systemColorsDidChangeNotification)
        let choice = WhatsNewChoice()
        choice.recent()
        print("language: \(Bundle.main.preferredLocalizations.first ?? "?")")
        var failed = false
        let pages: [(name: String, showsPro: Bool)] = [
            ("whats-new", Edition.showsProOffer),
            ("whats-new without Pro", false),
            ("how-to-use", false),
        ]
        for (name, showsPro) in pages {
            let isWhatsNew = name.hasPrefix("whats-new")
            for visibleHeight in [nil, shortScreen] {
                // Never started, so it checks for nothing; a change is sent by hand, as when a
                // check ends while the window is open.
                let updates = UpdateChecker(source: UpdateBuild.source())
                let controller: InfoWindowController = isWhatsNew
                    ? .whatsNew(updates: updates, accent: accent, choice: choice, showsPro: showsPro)
                    : .help(accent: accent)
                let screen = visibleHeight.map { "short screen \(Int($0))" } ?? "this screen"
                let steps = ["opened", "after a change", "opened again"]
                for step in steps where isWhatsNew || step != "after a change" {
                    switch step {
                    case "after a change":
                        updates.objectWillChange.send()
                    case "opened again":
                        controller.close()
                        await settle(0.3)
                        controller.show(visibleHeight: visibleHeight)
                    default:
                        controller.show(visibleHeight: visibleHeight)
                    }
                    await settle(1.5)
                    if let line = report(controller) {
                        print("\(name), \(screen), \(step): \(line)")
                    } else {
                        print("\(name), \(screen), \(step): not measured")
                        failed = true
                    }
                }
                controller.close()
                await settle(0.3)
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
            "key \(window.isKeyWindow)",
            "active \(NSApp.isActive)",
        ].joined(separator: ", ")
    }

    /// Waits while the app's own run loop goes on, so the app becomes active and the window key
    /// as when the menu opens it.
    private static func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}

/// Runs `InfoWindowMeasure` the way the app runs: as a SwiftUI app, without a menu bar item.
struct InfoWindowMeasureApp: App {
    @NSApplicationDelegateAdaptor(InfoWindowMeasureDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class InfoWindowMeasureDelegate: NSObject, NSApplicationDelegate {
    // Each window is closed before the next opens; the measure ends only when it is done.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            exit(await InfoWindowMeasure.run())
        }
    }
}
