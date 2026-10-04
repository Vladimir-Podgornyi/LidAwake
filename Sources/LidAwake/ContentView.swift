import AppKit
import LidAwakeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ModeController
    @ObservedObject var helper: HelperClient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LidAwake")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                modeRow(.off, title: "Off")
                modeRow(.keepScreenOn, title: "Keep Screen On")
                modeRow(.lidClosed, title: "Run with Lid Closed")
            }
            .disabled(controller.isBusy)

            helperRow

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit LidAwake") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260, alignment: .leading)
        .task { await helper.refresh() }
    }

    private var helperRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(helperStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(helperActionTitle) {
                helperAction()
            }
            .disabled(helper.isBusy)
        }
    }

    private var helperStatus: String {
        switch helper.state {
        case .notInstalled: return "Helper: not installed"
        case .requiresApproval: return "Helper: waiting for approval"
        case .ready: return "Helper: ready"
        case .error(let message): return "Helper: \(message)"
        case .outdated: return "Helper: outdated"
        }
    }

    private var helperActionTitle: String {
        switch helper.state {
        case .notInstalled, .error, .outdated: return "Install Helper"
        case .requiresApproval: return "Open System Settings"
        case .ready: return "Remove Helper"
        }
    }

    private func helperAction() {
        switch helper.state {
        case .notInstalled, .error, .outdated:
            Task { await helper.install() }
        case .requiresApproval:
            helper.openSystemSettings()
        case .ready:
            Task { await helper.uninstall() }
        }
    }

    private func modeRow(_ mode: Mode, title: String) -> some View {
        Button {
            Task { try? await controller.select(mode) }
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
