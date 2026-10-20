import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI
import UniformTypeIdentifiers

/// `--render-window <folder>`: draws the window with default settings in the Off and the
/// Keep Screen On positions, with the settings collapsed and expanded, Off with the update
/// banner, Keep Screen On with the automatic logout warning, Off expanded in a window limited
/// to 600 points, Keep Screen On expanded with both banners, Run with Lid Closed expanded with
/// Only while charging on, Run with Lid Closed expanded with Sleep when idle on and a made-up
/// idle state, Run with Lid Closed expanded with Wake at on as well, and Run with Lid Closed expanded
/// with made-up watched apps, without touching the helper, the login item, the display, the network or the saved settings.
/// It also draws the content of the wake time popover, the activity log window from made-up
/// entries, with the log file left alone, and the Watched Apps window with made-up apps, also with
/// the list in focus and one row chosen.
enum WindowSnapshot {
    static let flag = "--render-window"

    /// nil when the flag is absent; `.failure` when it has no folder after it.
    static func folder(from arguments: [String]) -> Result<URL, UsageError>? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, !arguments[next].isEmpty, !arguments[next].hasPrefix("-") else {
            return .failure(UsageError())
        }
        return .success(URL(fileURLWithPath: arguments[next], isDirectory: true))
    }

    struct UsageError: Error {
        let message = "usage: LidAwake --render-window <folder>"
    }

    @MainActor
    static func run(folder: URL) -> Int32 {
        // Switches and segmented controls draw their colored look only in the key window of
        // the active app. The app is not activated, so the focus stays where it is; it only
        // reports itself active, which lets the offscreen window become key.
        _ = ActiveLookingApplication.shared
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for shot in Shot.all {
                let file = folder.appendingPathComponent(shot.fileName)
                try render(shot).write(to: file)
                print(file.path)
            }
            for isDark in [false, true] {
                let file = folder.appendingPathComponent("wake-time-picker-\(isDark ? "dark" : "light").png")
                try renderWakeTimePicker(isDark: isDark).write(to: file)
                print(file.path)
            }
            for shot in LogShot.all {
                let file = folder.appendingPathComponent(shot.fileName)
                try render(shot).write(to: file)
                print(file.path)
            }
            for isChosen in [false, true] {
                for isDark in [false, true] {
                    let name = "watched-apps-\(isChosen ? "chosen-" : "")\(isDark ? "dark" : "light").png"
                    let file = folder.appendingPathComponent(name)
                    try renderWatchedApps(isDark: isDark, isChosen: isChosen).write(to: file)
                    print(file.path)
                }
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("render-window: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private struct Shot {
        let mode: Mode
        let isExpanded: Bool
        let isDark: Bool
        var showsUpdate = false
        var showsAutoLogout = false
        var chargingOnly = false
        var wakeOn = false
        var watched: [String] = []
        /// Turns Sleep when idle on and stands in for the helper's answer.
        var idle: IdleStatus?
        var maxHeight: CGFloat?
        var name: String?

        static let all = [
            Shot(mode: .off, isExpanded: false, isDark: false),
            Shot(mode: .off, isExpanded: true, isDark: false),
            Shot(mode: .off, isExpanded: true, isDark: true),
            Shot(mode: .keepScreenOn, isExpanded: false, isDark: false),
            Shot(mode: .keepScreenOn, isExpanded: true, isDark: false),
            Shot(mode: .off, isExpanded: false, isDark: false, showsUpdate: true),
            Shot(mode: .keepScreenOn, isExpanded: false, isDark: false, showsAutoLogout: true),
            Shot(mode: .off, isExpanded: true, isDark: false, maxHeight: 600, name: "off-expanded-short-light.png"),
            Shot(
                mode: .keepScreenOn,
                isExpanded: true,
                isDark: false,
                showsUpdate: true,
                showsAutoLogout: true,
                name: "screen-expanded-full-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: false,
                chargingOnly: true,
                name: "lid-expanded-charging-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: false,
                idle: idleStatus(.busyApp, holders: ["Example App"]),
                name: "lid-expanded-idle-app-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: false,
                idle: idleStatus(.counting, counted: 7),
                name: "lid-expanded-idle-counting-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: true,
                idle: idleStatus(.counting, counted: 7),
                name: "lid-expanded-idle-counting-dark.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: false,
                wakeOn: true,
                idle: idleStatus(.counting, counted: 7),
                name: "lid-expanded-wake-idle-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: false,
                watched: WatchedAppsShot.watched,
                name: "lid-expanded-watched-light.png"
            ),
            Shot(
                mode: .lidClosed,
                isExpanded: true,
                isDark: true,
                watched: WatchedAppsShot.watched,
                name: "lid-expanded-watched-dark.png"
            ),
        ]

        private static func idleStatus(_ state: IdleState, counted: Int = 0, holders: [String] = []) -> IdleStatus {
            IdleStatus(
                state: state,
                countedMinutes: counted,
                requiredMinutes: 20,
                cores: 0.2,
                inputIdleSeconds: 600,
                holders: holders
            )
        }

        var fileName: String {
            if let name {
                return name
            }
            if showsUpdate {
                return "off-update-\(isDark ? "dark" : "light").png"
            }
            if showsAutoLogout {
                return "screen-autologout-\(isDark ? "dark" : "light").png"
            }
            let position = mode == .off ? "off" : "screen"
            return "\(position)-\(isExpanded ? "expanded" : "collapsed")-\(isDark ? "dark" : "light").png"
        }

        var appearance: NSAppearance {
            NSAppearance(named: isDark ? .darkAqua : .aqua)!
        }
    }

    @MainActor
    private static func render(_ shot: Shot) throws -> Data {
        let appearance = shot.appearance
        // Only read: register(defaults:) stays in memory, so nothing is saved.
        let defaults = UserDefaults(suiteName: "com.vladimirpodgornyi.LidAwake.window-snapshot")!
        // An empty string is not a version, so the other shots have no update banner.
        defaults.register(defaults: [
            SettingsDisclosurePreference.key: shot.isExpanded,
            UpdateChecker.latestVersionKey: shot.showsUpdate ? "9.9.9" : "",
        ])
        // SafetyPreferences registers its own defaults over these, so the setting goes in the
        // argument domain, which is searched first and kept only in memory.
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var shotArguments = arguments
        shotArguments[SafetyPreferences.Key.chargingOnlyEnabled] = shot.chargingOnly
        shotArguments[SafetyPreferences.Key.idleSleepEnabled] = shot.idle != nil
        shotArguments[SafetyPreferences.Key.idleSleepMinutes] = 20
        shotArguments[WakePreferences.Key.wakeEnabled] = shot.wakeOn
        shotArguments[SafetyPreferences.Key.watchedAppPaths] = shot.watched
        shotArguments[WakePreferences.Key.wakeMinuteOfDay] = WakePreferences.defaultMinuteOfDay
        UserDefaults.standard.setVolatileDomain(shotArguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        let inert = Inert()
        let controller = ModeController(
            displayAssertion: inert,
            helper: inert,
            sessions: inert,
            preferences: SafetyPreferences(defaults: defaults),
            notifier: inert,
            activity: inert,
            powerSourceMonitor: inert,
            lidMonitor: inert
        )
        // The display assertion and the helper are inert, so selecting a mode keeps nothing awake.
        Task { try? await controller.select(shot.mode) }
        let deadline = Date(timeIntervalSinceNow: 2)
        while controller.mode != shot.mode, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        guard controller.mode == shot.mode else { throw CocoaError(.fileWriteUnknown) }
        // The helper is never ready here, so the scheduler makes no call.
        let wake = WakeScheduler(
            preferences: WakePreferences(defaults: defaults),
            helper: inert,
            service: inert,
            mode: controller,
            log: inert,
            clockMonitor: inert
        )
        let content = ContentView(
            controller: controller,
            preferences: controller.preferences,
            helperSetup: HelperSetup(helper: inert, selectMode: { _ in }),
            launchAtLogin: LaunchAtLogin(
                service: inert,
                store: inert,
                bundleURL: URL(fileURLWithPath: "/Applications/LidAwake.app")
            ),
            accent: AccentPreference(defaults: defaults),
            windowStyle: WindowAppearancePreference(defaults: defaults),
            disclosure: SettingsDisclosurePreference(defaults: defaults),
            updates: UpdateChecker(defaults: defaults, source: inert),
            // The other shots do not depend on the setting of this Mac.
            autoLogout: AutoLogoutMonitor(
                source: FixedAutoLogout(delay: shot.showsAutoLogout ? 3600 : nil),
                defaults: defaults
            ),
            wake: wake,
            wakePreferences: wake.preferences,
            idleSource: FixedIdleStatus(status: shot.idle),
            openActivityLog: {},
            openWatchedApps: {},
            // The offscreen window has no screen, so the limit is set here or not at all.
            heightLimit: .fixed(shot.maxHeight)
        )
        .background(Color(nsColor: .windowBackgroundColor))

        let host = NSHostingView(rootView: content)
        let window = SnapshotWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        // The measured heights decide whether the lower part scrolls, so fit the window again.
        window.setContentSize(host.fittingSize)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        return try png(of: host, appearance: appearance)
    }

    /// The popover's own frame is drawn by the system and is not in the picture.
    @MainActor
    private static func renderWakeTimePicker(isDark: Bool) throws -> Data {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: WakeTimePicker(minuteOfDay: .constant(WakePreferences.defaultMinuteOfDay)))
        let window = SnapshotWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 100, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        return try png(of: host, appearance: appearance)
    }

    @MainActor
    private static func render(_ shot: LogShot) throws -> Data {
        let content = ActivityLogContent(
            entries: shot.isEmpty ? [] : LogShot.entries,
            now: LogShot.now,
            accent: Palette.accent(.blue),
            clear: {}
        )
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let window = SnapshotWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: ActivityLogWindowController.width, height: shot.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = shot.appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        return try png(of: host, appearance: shot.appearance)
    }

    @MainActor
    private static func renderWatchedApps(isDark: Bool, isChosen: Bool) throws -> Data {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        let list = WatchedAppList.make(
            running: WatchedAppsShot.running,
            watched: WatchedAppsShot.watched,
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            ownPath: Bundle.main.bundleURL.path,
            name: AppDisplayName.of
        )
        let keyboard = WatchedAppsKeyboard(
            cursor: WatchedAppCursor(rows: list.rowPaths, selected: isChosen ? WatchedAppsShot.chosen : nil),
            hasKeys: isChosen
        )
        let content = WatchedAppsContent(
            list: list,
            busy: WatchedAppsShot.busy,
            canAdd: true,
            accent: Palette.accent(.blue),
            // The made-up apps have no icons of their own.
            icon: { _ in NSWorkspace.shared.icon(for: .applicationBundle) },
            keyboard: keyboard,
            setWatched: { _, _ in },
            toggle: { _ in },
            addOtherApp: {},
            done: {}
        )
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        let window = SnapshotWindow(
            contentRect: NSRect(
                x: -10_000,
                y: -10_000,
                width: WatchedAppsWindowController.width,
                height: WatchedAppsWindowController.initialHeight
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        return try png(of: host, appearance: appearance)
    }

    @MainActor
    private static func png(of host: NSView, appearance: NSAppearance) throws -> Data {
        let size = host.bounds.size
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = size
        // Filled first, so the PNG is opaque even where the window itself would show through.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}

/// The log window with entries of every kind over three days, or with none. The shots are drawn
/// in the window's content only, without the title bar.
private struct LogShot {
    let isDark: Bool
    let isEmpty: Bool

    static let all = [
        LogShot(isDark: false, isEmpty: false),
        LogShot(isDark: true, isEmpty: false),
        LogShot(isDark: false, isEmpty: true),
    ]

    var fileName: String {
        "log-\(isEmpty ? "empty-" : "")\(isDark ? "dark" : "light").png"
    }

    /// Taller than the window opens, so every entry is in the picture; the empty log keeps the
    /// opening height.
    var height: CGFloat {
        isEmpty ? ActivityLogWindowController.initialHeight : 780
    }

    var appearance: NSAppearance {
        NSAppearance(named: isDark ? .darkAqua : .aqua)!
    }

    static let now = time(day: 12, hour: 15, minute: 40)

    static let entries: [ActivityEntry] = [
        ActivityEntry(time: time(day: 10, hour: 9, minute: 12), event: .modeOn(.keepScreenOn)),
        ActivityEntry(
            time: time(day: 10, hour: 10, minute: 12),
            event: .modeOff(.keepScreenOn, .stopped(.timer, timerSeconds: 3600))
        ),
        ActivityEntry(time: time(day: 10, hour: 21, minute: 30), event: .modeOn(.lidClosed)),
        ActivityEntry(time: time(day: 10, hour: 22, minute: 5), event: .paused),
        ActivityEntry(time: time(day: 10, hour: 22, minute: 20), event: .resumed),
        ActivityEntry(time: time(day: 11, hour: 8, minute: 30), event: .keptAwakeByApp("Example App")),
        ActivityEntry(time: time(day: 11, hour: 9, minute: 45), event: .keptAwakeByLoad(busiest: "example-tool")),
        ActivityEntry(time: time(day: 11, hour: 10, minute: 2), event: .keptAwakeByInput),
        ActivityEntry(time: time(day: 11, hour: 10, minute: 3), event: .idleStarted(minutes: 20)),
        ActivityEntry(
            time: time(day: 11, hour: 10, minute: 23),
            event: .modeOff(.lidClosed, .stopped(.idle, idleMinutes: 20))
        ),
        ActivityEntry(time: time(day: 11, hour: 10, minute: 24), event: .sleep),
        ActivityEntry(time: time(day: 12, hour: 7, minute: 58), event: .wake),
        ActivityEntry(time: time(day: 12, hour: 8, minute: 5), event: .modeOn(.lidClosed)),
        ActivityEntry(time: time(day: 12, hour: 9, minute: 40), event: .modeOff(.lidClosed, .user)),
    ]

    /// October 2026 in the time zone of this Mac, so the times read the same everywhere.
    private static func time(day: Int, hour: Int, minute: Int) -> Date {
        Calendar.autoupdatingCurrent.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
}

/// Made-up apps: two watched, one of them busy, a background agent that is left out, and one
/// watched app that is not open.
private enum WatchedAppsShot {
    static let watched = ["/Applications/Example Editor.app", "/Applications/Example Shell.app", "/Applications/Example Studio.app"]

    static let running = [
        RunningApp(path: "/Applications/Example Shell.app", name: "Example Shell", bundleIdentifier: "example.shell", isRegular: true),
        RunningApp(path: "/Applications/Example Editor.app", name: "Example Editor", bundleIdentifier: "example.editor", isRegular: true),
        RunningApp(path: "/Applications/Example Notes.app", name: "Example Notes", bundleIdentifier: "example.notes", isRegular: true),
        RunningApp(path: "/Applications/Example Browser.app", name: "Example Browser", bundleIdentifier: "example.browser", isRegular: true),
        RunningApp(path: "/Applications/Example Agent.app", name: "Example Agent", bundleIdentifier: "example.agent", isRegular: false),
    ]

    static let busy: Set<String> = ["/Applications/Example Editor.app"]

    /// The row chosen with the keys in the shots with the list in focus.
    static let chosen = "/Applications/Example Editor.app"
}

private struct FixedAutoLogout: AutoLogoutSource {
    let delay: Int?

    func delaySeconds() -> Int? { delay }
}

/// Answers as the helper would, or fails like a helper that cannot be reached.
private struct FixedIdleStatus: IdleStatusReading {
    let status: IdleStatus?

    func idleStatus() async throws -> IdleStatus {
        guard let status else { throw CancellationError() }
        return status
    }
}

private final class ActiveLookingApplication: NSApplication {
    override var isActive: Bool { true }
}

/// A borderless window cannot become key by default.
private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Stands in for everything outside the window, so drawing it has no effect.
@MainActor
private final class Inert: PowerAssertion, HelperPreparing, HelperInstalling, LidSessionService, StopNotifying,
    ActivityHolding, PowerSourceMonitoring, LidMonitoring, LoginItemService, LaunchAtLoginStore, ReleaseSource,
    ScheduledWakeService, ActivityLogging, ClockChangeMonitoring {
    nonisolated var isHeld: Bool { false }
    nonisolated func acquire() throws {}
    nonisolated func release() {}

    func prepareForSession() async throws {}
    func isReady() async -> Bool { false }

    var state: HelperState { .ready }
    var isInApplications: Bool { true }
    func refresh() async {}
    func install() async {}
    func openSystemSettings() {}

    nonisolated func startSession(leaseSeconds: Int, safety: SafetySettings) async throws {}
    nonisolated func renewSession(leaseSeconds: Int, safety: SafetySettings) async throws { throw CancellationError() }
    nonisolated func endSession() async throws {}
    nonisolated func clearLeftover() async throws {}
    nonisolated func sessionStatus() async throws -> HelperSessionStatus { throw CancellationError() }
    nonisolated func lastStopReason() async throws -> StopRecord? { nil }
    nonisolated func clearStopReason() async throws {}

    func requestAuthorization() {}
    func post(title: String, body: String) {}

    nonisolated func begin() {}
    nonisolated func end() {}

    nonisolated func start(_ handler: @escaping () -> Void) {}
    nonisolated func start(_ handler: @escaping (_ closed: Bool) -> Void) {}

    nonisolated var status: LoginItemStatus { .enabled }
    nonisolated func register() throws {}
    nonisolated func unregister() throws {}

    nonisolated func setScheduledWake(minuteOfDay: Int) async throws {}
    nonisolated func scheduledWakes() async throws -> [Date] { [] }

    func record(_ event: ActivityEvent, at time: Date?) {}

    nonisolated func latestRelease() async throws -> ReleaseLookup { throw CancellationError() }

    nonisolated var isInitialized: Bool {
        get { true }
        set {}
    }
}
