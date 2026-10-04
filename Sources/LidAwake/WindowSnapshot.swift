import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI

/// `--render-window <folder>`: draws the window in the Off mode with default settings
/// into window-light.png and window-dark.png, without touching the helper,
/// the login item or the saved settings.
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
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let file = folder.appendingPathComponent("window-\(name).png")
                try render(appearance: NSAppearance(named: appearance)!).write(to: file)
                print(file.path)
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("render-window: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    @MainActor
    private static func render(appearance: NSAppearance) throws -> Data {
        // Only read: register(defaults:) stays in memory, so nothing is saved.
        let defaults = UserDefaults(suiteName: "com.vladimirpodgornyi.LidAwake.window-snapshot")!
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
            windowStyle: WindowAppearancePreference(defaults: defaults)
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
        host.layoutSubtreeIfNeeded()
        defer { window.close() }

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
    ActivityHolding, PowerSourceMonitoring, LidMonitoring, LoginItemService, LaunchAtLoginStore {
    nonisolated var isHeld: Bool { false }
    nonisolated func acquire() throws {}
    nonisolated func release() {}

    func prepareForSession() async throws { throw CancellationError() }
    func isReady() async -> Bool { false }

    var state: HelperState { .ready }
    var isInApplications: Bool { true }
    func refresh() async {}
    func install() async {}
    func openSystemSettings() {}

    nonisolated func startSession(leaseSeconds: Int, safety: SafetySettings) async throws { throw CancellationError() }
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

    nonisolated var isInitialized: Bool {
        get { true }
        set {}
    }
}
