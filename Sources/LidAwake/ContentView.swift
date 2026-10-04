import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ModeController
    @ObservedObject var preferences: SafetyPreferences
    @ObservedObject var helper: HelperClient

    private let power = IOKitPowerSource()

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

            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if let status = statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            safetyRows

            Divider()

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
        .frame(width: 300, alignment: .leading)
        .task { await helper.refresh() }
    }

    private var statusLine: String? {
        if controller.mode == .lidClosed && controller.isPaused {
            return "Paused · on battery"
        }
        var parts: [String] = []
        if let remaining = controller.timerRemaining() {
            parts.append("\(Self.duration(Int(remaining.rounded(.up)))) left")
        }
        switch power.read().battery {
        case .percent(let percent): parts.append("Battery \(percent)%")
        case .unknown: parts.append("Battery unknown")
        case .none: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var safetyRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Only the timer applies to Keep Screen On.
            Toggle("Stop when the Mac gets hot", isOn: $preferences.thermalProtectionEnabled)
                .opacity(controller.mode == .keepScreenOn ? 0.4 : 1)
            HStack {
                Toggle("Stop on low battery", isOn: $preferences.batteryLimitEnabled)
                Spacer()
                Picker("Stop on low battery", selection: $preferences.batteryLimitPercent) {
                    ForEach(
                        Self.choices(SafetyPreferences.batteryLimitChoices, current: preferences.batteryLimitPercent),
                        id: \.self
                    ) {
                        Text("\($0)%").tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!preferences.batteryLimitEnabled)
            }
            .opacity(controller.mode == .keepScreenOn ? 0.4 : 1)
            Toggle("Only while charging", isOn: $preferences.chargingOnlyEnabled)
                .opacity(controller.mode == .keepScreenOn ? 0.4 : 1)
            HStack {
                Toggle("Turn off after", isOn: $preferences.timerEnabled)
                Spacer()
                Picker("Turn off after", selection: $preferences.timerSeconds) {
                    ForEach(Self.choices(SafetyPreferences.timerChoices, current: preferences.timerSeconds), id: \.self) {
                        Text(Self.timerLabel($0)).tag($0)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!preferences.timerEnabled)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private static func choices(_ list: [Int], current: Int) -> [Int] {
        list.contains(current) ? list : (list + [current]).sorted()
    }

    private static func timerLabel(_ seconds: Int) -> String {
        switch seconds {
        case 1800: return "30 min"
        case 3600: return "1 hour"
        case 7200: return "2 hours"
        case 14_400: return "4 hours"
        case 28_800: return "8 hours"
        default: return duration(seconds)
        }
    }

    private static func duration(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
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
