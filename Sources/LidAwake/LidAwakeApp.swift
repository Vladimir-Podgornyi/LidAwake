import SwiftUI

@main
struct LidAwakeApp: App {
    var body: some Scene {
        MenuBarExtra("LidAwake", systemImage: "laptopcomputer") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
