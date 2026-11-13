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
    let powerStatus = PowerStatus()
    let whatsNewChoice = WhatsNewChoice()
    let sleepRecorder: SystemSleepRecorder
    let wakeScheduler: WakeScheduler
    private(set) lazy var activityLogWindow = ActivityLogWindowController(log: activityLog, accent: accent)
    private(set) lazy var watchedAppsWindow = WatchedAppsWindowController(
        preferences: modeController.preferences,
        accent: accent
    )
    private(set) lazy var whatsNewWindow = InfoWindowController.whatsNew(
        updates: updates,
        accent: accent,
        choice: whatsNewChoice,
        showsPro: Edition.showsProOffer && !WithoutProOffer.isEnabled
    )
    private(set) lazy var helpWindow = InfoWindowController.help(accent: accent)

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
        openWhatsNewOnFirstLaunch()
        Task {
            await helperClient.updateIfOutdated()
            await modeController.clearLeftover()
            await wakeScheduler.appDidLaunch()
        }
    }

    /// On the first launch of a build with new news, with every version missed since the window
    /// last opened; a moment after launch, so the menu bar icon is in place first.
    private func openWhatsNewOnFirstLaunch() {
        let launch = WhatsNewLaunch()
        guard launch.opensByItself(version: Edition.whatsNewVersion) else { return }
        let lastShown = launch.lastShownVersion
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            launch.markShown(version: Edition.whatsNewVersion)
            self?.whatsNewChoice.sinceLastShown(lastShown)
            self?.whatsNewWindow.show()
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
                powerStatus: appDelegate.powerStatus,
                idleSource: XPCHelperConnection(),
                openActivityLog: {
                    // The row is in the menu bar window, which is key while it is open.
                    if let window = NSApp.keyWindow {
                        MenuBarWindow.close(window)
                    }
                    appDelegate.activityLogWindow.show()
                },
                openWatchedApps: {
                    if let window = NSApp.keyWindow {
                        MenuBarWindow.close(window)
                    }
                    appDelegate.watchedAppsWindow.show()
                },
                openWhatsNew: {
                    if let window = NSApp.keyWindow {
                        MenuBarWindow.close(window)
                    }
                    appDelegate.whatsNewChoice.recent()
                    appDelegate.whatsNewWindow.show()
                },
                openHowToUse: {
                    if let window = NSApp.keyWindow {
                        MenuBarWindow.close(window)
                    }
                    appDelegate.helpWindow.show()
                }
            )
        } label: {
            MenuBarIcon(controller: appDelegate.modeController)
        }
        .menuBarExtraStyle(.window)
    }
}
