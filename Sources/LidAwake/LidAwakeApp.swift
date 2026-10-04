import AppKit
import LidAwakeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let helperClient: HelperClient
    let modeController: ModeController
    let helperSetup: HelperSetup

    override init() {
        helperClient = HelperClient()
        let controller = ModeController(
            helper: helperClient,
            sessions: XPCHelperConnection(),
            preferences: SafetyPreferences(),
            notifier: UserNotificationNotifier()
        )
        modeController = controller
        helperSetup = HelperSetup(helper: helperClient) { try await controller.select($0) }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await helperClient.updateIfOutdated()
            await modeController.clearLeftover()
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
}

struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                controller: appDelegate.modeController,
                preferences: appDelegate.modeController.preferences,
                helperSetup: appDelegate.helperSetup
            )
        } label: {
            MenuBarIcon(controller: appDelegate.modeController)
        }
        .menuBarExtraStyle(.window)
    }
}
