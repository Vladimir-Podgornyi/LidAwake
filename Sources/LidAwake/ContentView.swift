import AppKit
import LidAwakeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ModeController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LidAwake")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                modeRow(.off, title: "Off")
                modeRow(.keepScreenOn, title: "Keep Screen On")
                modeRow(.lidClosed, title: "Run with Lid Closed")
                    .disabled(true)
            }

            Divider()

            Button("Quit LidAwake") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260, alignment: .leading)
    }

    private func modeRow(_ mode: Mode, title: String) -> some View {
        Button {
            try? controller.select(mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(controller.mode == mode ? 1 : 0)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
