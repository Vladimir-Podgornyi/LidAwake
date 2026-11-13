import AppKit
import LidAwakeCore
import SwiftUI

/// `--measure-mode-switch`: opens the menu bar window, as a click on the icon does, with
/// everything outside the window inert, as the shots draw it, and switches Off → Keep Screen On →
/// Run with Lid Closed → Keep Screen On → Off. While each switch runs, it prints the window's height and top edge
/// and the height of every mode card each time one of them changes; after the window opens and
/// after each switch, the system focus rings on the cards. Then it quits. With
/// `--reduced-motion` the window switches as with Reduce motion on; with `--expanded` the
/// settings are expanded. The card focus needs Keyboard navigation on.
enum ModeSwitchMeasure {
    static let flag = "--measure-mode-switch"
    static let isReducingMotion = CommandLine.arguments.contains("--reduced-motion")
    static let isExpanded = CommandLine.arguments.contains("--expanded")

    @MainActor
    static let window = WindowSnapshot.inertWindow(isExpanded: isExpanded, reducesMotion: isReducingMotion) { mode, height in
        cardHeights[mode] = height
    }

    @MainActor
    private static var cardHeights: [Mode: CGFloat] = [:]

    private struct Sample: Equatable {
        var windowHeight: CGFloat
        var windowTop: CGFloat
        var cards: [CGFloat]
        var mode: Mode
        var shownMode: Mode
    }

    @MainActor
    static func run() async -> Int32 {
        defer { WindowSnapshot.removeInertSettings() }
        print("language: \(Bundle.main.preferredLocalizations.first ?? "?"), reduce motion: \(isReducingMotion), settings expanded: \(isExpanded)")
        await settle(0.5)
        guard let button = MenuBarWindow.statusButton() else {
            print("no menu bar icon")
            return 1
        }
        button.performClick(nil)
        await settle(0.8)
        guard let window = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).hasPrefix("MenuBarExtraWindow") }) else {
            print("the window did not open")
            return 1
        }
        // macOS may keep another app active while someone works in it; the heights do not
        // depend on it, the card focus does.
        if !window.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            await settle(0.5)
        }
        print("window: \(type(of: window)), key: \(window.isKeyWindow)")
        let controller = Self.window.controller
        print(focusRings(in: window, controller: controller))
        var failed = false
        for mode in [Mode.keepScreenOn, .lidClosed, .keepScreenOn, .off] {
            failed = await measure(switchingTo: mode, in: window, controller: controller) || failed
            print(focusRings(in: window, controller: controller))
        }
        MenuBarWindow.close(window)
        return failed ? 1 : 0
    }

    /// Returns true when a card could not be measured.
    @MainActor
    private static func measure(switchingTo mode: Mode, in window: NSWindow, controller: ModeController) async -> Bool {
        let from = controller.shownMode
        print("")
        print("\(from) → \(mode)")
        print("    ms  window   top     cards (Off, Keep Screen On, Run with Lid Closed)   mode → shown")
        let start = Date()
        var samples: [(ms: Int, sample: Sample)] = []
        var last: Sample?
        var ticks = 0
        var lastTick = Date()
        var longestGap: TimeInterval = 0
        func take() {
            ticks += 1
            longestGap = max(longestGap, Date().timeIntervalSince(lastTick))
            lastTick = Date()
            guard let sample = sample(window, controller: controller), sample != last else { return }
            last = sample
            let ms = Int((Date().timeIntervalSince(start) * 1000).rounded())
            samples.append((ms, sample))
            let cards = sample.cards.map { f($0) }.joined(separator: " ")
            print("\(String(format: "%6d", ms))  \(f(sample.windowHeight))  \(f(sample.windowTop))  \(cards)   \(sample.mode) → \(sample.shownMode)")
        }
        take()
        // Several times a frame, so no frame of the window is missed.
        let timer = Timer(timeInterval: 1.0 / 480, repeats: true) { _ in
            MainActor.assumeIsolated { take() }
        }
        RunLoop.main.add(timer, forMode: .common)
        Task { try? await controller.select(mode) }
        await settle(0.9)
        timer.invalidate()
        print("samples taken: \(ticks) in 900 ms, longest gap \(Int(longestGap * 1000)) ms")
        guard let first = samples.first?.sample, let end = samples.last?.sample, first.cards.count == Mode.allCases.count else {
            print("cards not found")
            return true
        }
        let folded = samples.flatMap(\.sample.cards).min() ?? 0
        // A card is open when it is taller than a card with its title only.
        let noneOpen = samples.filter { !$0.sample.cards.contains { $0 > folded + 1 } }.count
        let heights = samples.map(\.sample.windowHeight)
        let tops = Set(samples.map(\.sample.windowTop))
        let changes = zip(heights, heights.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
        let steps = changes.map { abs($0) }
        print("window \(f(first.windowHeight)) → \(f(end.windowHeight)), \(changes.count) height changes, largest step \(f(steps.max() ?? 0)), all steps in one direction: \(Set(changes.map { $0 > 0 }).count <= 1)")
        print("top edge positions: \(tops.map(f).sorted().joined(separator: ", "))")
        print("samples where no card is open: \(noneOpen)")
        print("shown modes: \(dedup(samples.map(\.sample.shownMode)).map { "\($0)" }.joined(separator: " → ")); modes: \(dedup(samples.map(\.sample.mode)).map { "\($0)" }.joined(separator: " → "))")
        return false
    }

    @MainActor
    private static func sample(_ window: NSWindow, controller: ModeController) -> Sample? {
        let cards = Mode.allCases.compactMap { cardHeights[$0] }
        guard cards.count == Mode.allCases.count else { return nil }
        return Sample(
            windowHeight: window.frame.height,
            windowTop: window.frame.maxY,
            cards: cards,
            mode: controller.mode,
            shownMode: controller.shownMode
        )
    }

    /// The system focus rings in the window: SwiftUI draws each as an AppKit view of its own,
    /// one for every control that can take the focus. The ones above the bottom of the last card
    /// are the cards'; with the cards' own rings there should be none, or only hidden ones.
    @MainActor
    private static func focusRings(in window: NSWindow, controller: ModeController) -> String {
        guard let content = window.contentView else { return "focus rings: no content" }
        var rings: [(frame: NSRect, isHidden: Bool)] = []
        func collect(_ view: NSView) {
            if String(describing: type(of: view)).hasSuffix("_FocusRingView") {
                var frame = view.convert(view.bounds, to: content)
                if !content.isFlipped {
                    frame.origin.y = content.bounds.height - frame.maxY
                }
                rings.append((frame, view.isHidden))
            }
            view.subviews.forEach(collect)
        }
        collect(content)
        let cardsBottom = 14 + 16 + 12 + cardHeights.values.reduce(0, +) + 8 * CGFloat(Mode.allCases.count - 1) + 4
        let onCards = rings.filter { $0.frame.minY < cardsBottom }
        let list = onCards.map { "y \(Int($0.frame.minY)) h \(Int($0.frame.height))\($0.isHidden ? " hidden" : " visible")" }
        return "system focus rings on the mode cards (selected \(controller.shownMode)): \(list.isEmpty ? "none" : list.joined(separator: ", ")); elsewhere: \(rings.count - onCards.count)"
    }

    private static func dedup(_ modes: [Mode]) -> [Mode] {
        modes.reduce(into: []) { result, mode in
            if result.last != mode { result.append(mode) }
        }
    }

    private static func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%6.1f", value)
    }
}

/// Runs `ModeSwitchMeasure` in a menu bar window of its own, as the app does.
struct ModeSwitchMeasureApp: App {
    @NSApplicationDelegateAdaptor(ModeSwitchMeasureDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ModeSwitchMeasure.window.content
        } label: {
            Image(systemName: "ruler")
        }
        .menuBarExtraStyle(.window)
    }
}

final class ModeSwitchMeasureDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            exit(await ModeSwitchMeasure.run())
        }
    }
}
