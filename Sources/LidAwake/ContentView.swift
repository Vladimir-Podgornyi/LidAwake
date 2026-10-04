import AppKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LidAwake")
                .font(.headline)

            Divider()

            Button("Quit LidAwake") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260, alignment: .leading)
    }
}
