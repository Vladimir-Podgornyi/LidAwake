import AppKit
import LidAwakeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let helperClient: HelperClient
    let modeController: ModeController
    let helperSetup: HelperSetup
    let launchAtLogin = LaunchAtLogin()
    let accent = AccentPreference(systemColorsChanged: NSColor.systemColorsDidChangeNotification)
    let windowStyle = WindowAppearancePreference()
    let settingsDisclosure = SettingsDisclosurePreference()
    let updates = UpdateChecker(source: UpdateBuild.source())
    let autoLogout = AutoLogoutMonitor()
    let activityLog = ActivityLog()
    let sleepRecorder: SystemSleepRecorder
    let wakeScheduler: WakeScheduler
    private(set) lazy var activityLogWindow = ActivityLogWindowController(log: activityLog, accent: accent)

    override init() {
        helperClient = HelperClient()
        let controller = ModeController(
            helper: helperClient,
            sessions: XPCHelperConnection(),
            preferences: SafetyPreferences(),
            notifier: UserNotificationNotifier(),
            activityLog: activityLog,
            idleEvents: XPCHelperConnection()
        )
        let scheduler = WakeScheduler(
            preferences: WakePreferences(),
            helper: helperClient,
            service: XPCHelperConnection(),
            mode: controller,
            log: activityLog
        )
        wakeScheduler = scheduler
        sleepRecorder = SystemSleepRecorder(log: activityLog, wakeHandler: scheduler)
        modeController = controller
        helperSetup = HelperSetup(
            helper: helperClient,
            dismissModeMessage: { controller.dismissMessage() },
            selectMode: { try await controller.select($0) },
            syncWake: { await scheduler.sync() }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin.enableOnFirstLaunch()
        sleepRecorder.start()
        wakeScheduler.start()
        updates.start()
        Task {
            await helperClient.updateIfOutdated()
            await modeController.clearLeftover()
            await wakeScheduler.appDidLaunch()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard modeController.mode != .off else { return .terminateNow }
        Task {
            try? await modeController.select(.off)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeScheduler.appWillTerminate()
    }
}

struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                controller: appDelegate.modeController,
                preferences: appDelegate.modeController.preferences,
                helperSetup: appDelegate.helperSetup,
                launchAtLogin: appDelegate.launchAtLogin,
                accent: appDelegate.accent,
                windowStyle: appDelegate.windowStyle,
                disclosure: appDelegate.settingsDisclosure,
                updates: appDelegate.updates,
                autoLogout: appDelegate.autoLogout,
                wake: appDelegate.wakeScheduler,
                wakePreferences: appDelegate.wakeScheduler.preferences,
                idleSource: XPCHelperConnection(),
                openActivityLog: {
                    // The row is in the menu bar window, which is key while it is open.
                    if let window = NSApp.keyWindow {
                        MenuBarWindow.close(window)
                    }
                    appDelegate.activityLogWindow.show()
                }
            )
        } label: {
            MenuBarIcon(controller: appDelegate.modeController)
        }
        .menuBarExtraStyle(.window)
    }
}
