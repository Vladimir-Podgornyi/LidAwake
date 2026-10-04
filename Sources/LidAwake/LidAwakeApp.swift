import AppKit
import LidAwakeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let helperClient: HelperClient
    let modeController: ModeController

    override init() {
        helperClient = HelperClient()
        modeController = ModeController(
            helper: helperClient,
            sessions: XPCHelperConnection(),
            preferences: SafetyPreferences(),
            notifier: UserNotificationNotifier()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await modeController.clearLeftover() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard modeController.mode != .off else { return .terminateNow }
        Task {
            try? await modeController.select(.off)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LidAwake", systemImage: "laptopcomputer") {
            ContentView(
                controller: appDelegate.modeController,
                preferences: appDelegate.modeController.preferences,
                helper: appDelegate.helperClient
            )
        }
        .menuBarExtraStyle(.window)
    }
}
