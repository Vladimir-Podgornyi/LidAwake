import AppKit
import LidAwakeCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let modeController = ModeController()

    func applicationWillTerminate(_ notification: Notification) {
        try? modeController.select(.off)
    }
}

@main
struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LidAwake", systemImage: "laptopcomputer") {
            ContentView(controller: appDelegate.modeController)
        }
        .menuBarExtraStyle(.window)
    }
}
