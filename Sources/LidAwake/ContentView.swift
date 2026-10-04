import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ModeController
    @ObservedObject var preferences: SafetyPreferences
    @ObservedObject var helperSetup: HelperSetup

    private let power = IOKitPowerSource()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modeCards
            if controller.lastError != nil || helperSetup.prompt != nil {
                messages
            }
            switch SafetyLayout(mode: controller.mode) {
            case .all: allProtections
            case .timerOnly: timerOnlyProtections
            }
            quitRow
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(width: 320, alignment: .leading)
        .tint(Palette.accent)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "LidAwake")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if let status = statusLine {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusLine: String? {
        StatusLine.text(
            mode: controller.mode,
            isPaused: controller.isPaused,
            timerRemaining: controller.timerRemaining(),
            battery: controller.mode == .lidClosed ? power.read().battery : .none
        )
    }

    private var modeCards: some View {
        VStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { mode in
                ModeCard(mode: mode, isSelected: controller.mode == mode) {
                    Task { await helperSetup.select(mode) }
                }
            }
        }
        .disabled(controller.isBusy)
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = controller.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prompt = helperSetup.prompt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.message)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionTitle = prompt.actionTitle {
                        Button(actionTitle) {
                            Task { await helperSetup.performPromptAction() }
                        }
                        .disabled(helperSetup.isWorking)
                    }
                }
            }
        }
    }

    // Off and Run with Lid Closed.
    private var allProtections: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Safety")
                SettingRow(title: "Stop when the Mac gets hot", detail: "Ends the session under thermal pressure") {
                    thermalToggle
                }
                SettingRow(title: "Stop on low battery", detail: "When the charge drops below the limit") {
                    batteryValue
                    batteryToggle
                }
                SettingRow(title: "Only while charging", detail: "Pauses on battery, resumes on power") {
                    chargingToggle
                }
                timerRow
            }
            Divider()
            lockRow(minHeight: 36)
            Divider()
        }
    }

    // Keep Screen On: only the timer applies.
    private var timerOnlyProtections: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Timer")
                timerRow
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Safety · lid closed only")
                SettingRow(title: "Stop when the Mac gets hot", minHeight: 40) {
                    thermalToggle
                }
                SettingRow(title: "Stop on low battery", minHeight: 40) {
                    batteryValue
                    batteryToggle
                }
                SettingRow(title: "Only while charging", minHeight: 40) {
                    chargingToggle
                }
                lockRow(minHeight: 40)
            }
            .opacity(0.45)
            .disabled(true)
            Divider()
        }
    }

    private var timerRow: some View {
        SettingRow(title: "Turn off after", detail: "Counts from the moment you switch on") {
            ValueMenu(
                label: "Turn off after",
                selection: $preferences.timerSeconds,
                choices: Self.choices(SafetyPreferences.timerChoices, current: preferences.timerSeconds),
                title: DurationFormat.choice
            )
            SwitchToggle(title: "Turn off after", isOn: $preferences.timerEnabled)
        }
    }

    private var thermalToggle: some View {
        SwitchToggle(title: "Stop when the Mac gets hot", isOn: $preferences.thermalProtectionEnabled)
    }

    private var batteryValue: some View {
        ValueMenu(
            label: "Battery limit",
            selection: $preferences.batteryLimitPercent,
            choices: Self.choices(SafetyPreferences.batteryLimitChoices, current: preferences.batteryLimitPercent),
            title: DurationFormat.percent
        )
    }

    private var batteryToggle: some View {
        SwitchToggle(title: "Stop on low battery", isOn: $preferences.batteryLimitEnabled)
    }

    private var chargingToggle: some View {
        SwitchToggle(title: "Only while charging", isOn: $preferences.chargingOnlyEnabled)
    }

    private func lockRow(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(title: "Lock screen when the lid closes", minHeight: minHeight) {
                SwitchToggle(title: "Lock screen when the lid closes", isOn: $preferences.lockOnLidCloseEnabled)
            }
            if let notice = controller.screenLockNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var quitRow: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack {
                Text("Quit LidAwake")
                    .font(.system(size: 13))
                Spacer()
                Text(verbatim: "⌘Q")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .accessibilityLabel(Text("Quit LidAwake"))
    }

    /// Keeps a stored value that is not one of the choices visible and selectable.
    private static func choices(_ list: [Int], current: Int) -> [Int] {
        list.contains(current) ? list : (list + [current]).sorted()
    }
}

private extension Mode {
    var title: LocalizedStringKey {
        switch self {
        case .off: return "Off"
        case .keepScreenOn: return "Keep Screen On"
        case .lidClosed: return "Run with Lid Closed"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .off: return "The Mac sleeps as usual."
        case .keepScreenOn: return "For stepping away from the desk. Closing the lid still puts the Mac to sleep."
        case .lidClosed: return "For the road. Keeps working with the lid shut or the screen locked."
        }
    }
}

private struct ModeCard: View {
    let mode: Mode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                ModeIconView(mode: mode)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isSelected ? Palette.accent : Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Palette.accent))
                        .accessibilityHidden(true)
                }
            }
            // The border is drawn inside the card, so 13 matches the mockup's 12 padding plus a 1 border.
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.cardBackground))
            .overlay(shape.strokeBorder(isSelected ? Palette.accent : Palette.cardBorder, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel(Text(mode.title))
        .accessibilityHint(Text(mode.summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingRow<Controls: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var minHeight: CGFloat = 44
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            controls
        }
        .frame(minHeight: minHeight)
    }
}

private struct SwitchToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// A value in a rounded "pill" that opens a menu of choices.
private struct ValueMenu: View {
    let label: LocalizedStringKey
    @Binding var selection: Int
    let choices: [Int]
    let title: (Int) -> String

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(choices, id: \.self) { value in
                    Text(title(value)).tag(value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(title(selection))
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // A borderless menu draws its title in the tint color.
        .tint(.primary)
        .fixedSize()
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.valueBackground))
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(title(selection)))
    }
}
