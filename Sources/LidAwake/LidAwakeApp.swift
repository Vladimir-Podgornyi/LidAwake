import AppKit
import LidAwakeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let modeController = ModeController()
    let helperClient = HelperClient()

    func applicationWillTerminate(_ notification: Notification) {
        try? modeController.select(.off)
    }
}

struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LidAwake", systemImage: "laptopcomputer") {
            ContentView(controller: appDelegate.modeController, helper: appDelegate.helperClient)
        }
        .menuBarExtraStyle(.window)
    }
}
