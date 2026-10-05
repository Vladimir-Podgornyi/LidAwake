import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ModeController
    @ObservedObject var preferences: SafetyPreferences
    @ObservedObject var helperSetup: HelperSetup
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var accent: AccentPreference
    @ObservedObject var windowStyle: WindowAppearancePreference
    @ObservedObject var disclosure: SettingsDisclosurePreference
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var autoLogout: AutoLogoutMonitor
    var heightLimit: HeightLimit = .screen

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var screenLimit: CGFloat?
    @State private var fixedHeight: CGFloat = 0
    @State private var scrollingContentHeight: CGFloat = 0

    private let power = IOKitPowerSource()
    private let isSystem26OrLater = WindowLook.isSystem26OrLater

    /// How tall the window may get.
    enum HeightLimit {
        /// The visible area of the screen the window is on, measured from the window's real frame.
        case screen
        /// A set height, or none.
        case fixed(CGFloat?)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                modeCards
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .padding(.horizontal, 14)
            .background(HeightReader(height: $fixedHeight))
            if let scrollHeight {
                // No background of its own, so Glass and Solid look the same as without scrolling.
                ScrollView(.vertical) {
                    scrollingContent
                }
                .frame(height: scrollHeight)
            } else {
                scrollingContent
            }
        }
        .frame(width: 320, alignment: .leading)
        .background(WindowGeometryReader(limit: $screenLimit, isScrolling: scrollHeight != nil))
        .background(look.drawsOwnBackground ? Palette.solidWindowBackground : .clear)
        .tint(accentColor)
        .onAppear {
            launchAtLogin.refresh()
            autoLogout.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin.refresh()
            autoLogout.refresh()
        }
        .onChange(of: controller.mode) { _ in autoLogout.refresh() }
    }

    /// Everything below the mode cards; it scrolls when the window would not fit on the screen.
    private var scrollingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !messages.isEmpty {
                messageBlock
            }
            ForEach(WindowBlockGroup.groups(blocks), id: \.self) { group in
                switch group {
                case .block(let block):
                    view(for: block)
                case .compactRows(let rows):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows, id: \.self) { block in
                            view(for: block, isCompact: true)
                        }
                    }
                }
            }
            quitRow
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .background(HeightReader(height: $scrollingContentHeight))
    }

    private var maxHeight: CGFloat? {
        switch heightLimit {
        case .screen: return screenLimit
        case .fixed(let height): return height
        }
    }

    private var scrollHeight: CGFloat? {
        WindowHeightLimit.scrollHeight(
            fixedHeight: fixedHeight,
            contentHeight: scrollingContentHeight,
            maxHeight: maxHeight
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "LidAwake")
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if let status = statusLine {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
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
                ModeCard(mode: mode, isSelected: controller.mode == mode, accent: accentColor, look: look) {
                    Task { await helperSetup.select(mode) }
                }
            }
        }
        .disabled(controller.isBusy)
    }

    private var messages: [WindowMessage] {
        WindowMessage.list(
            helper: helperSetup.prompt,
            mode: controller.message,
            autoLogout: autoLogout.notice(
                mode: controller.mode,
                timerSeconds: preferences.timerEnabled ? preferences.timerSeconds : nil
            ),
            update: updates.notice
        )
    }

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { message in
                MessageBanner(message: message, look: look, isActionDisabled: message.source == .helper && helperSetup.isWorking) {
                    switch message.source {
                    case .update:
                        NSWorkspace.shared.open(UpdateLinks.downloadPage)
                    case .autoLogout:
                        openAutoLogoutSettings()
                    case .helper, .mode:
                        Task { await helperSetup.performPromptAction() }
                    }
                }
            }
        }
    }

    /// Tries the Advanced anchor first; if System Settings refuses it, opens the section.
    private func openAutoLogoutSettings() {
        NSWorkspace.shared.open(AutoLogoutLinks.advancedSettings, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(AutoLogoutLinks.privacySettings)
            }
        }
    }

    private var blocks: [WindowBlock] {
        WindowBlock.list(
            mode: controller.mode,
            isExpanded: disclosure.isExpanded,
            showsAppearance: WindowLook.showsStyleSetting(isSystem26OrLater: isSystem26OrLater)
        )
    }

    @ViewBuilder
    private func view(for block: WindowBlock, isCompact: Bool = false) -> some View {
        switch block {
        case .timer: timerSection
        case .settingsToggle: SettingsToggleRow(isExpanded: $disclosure.isExpanded)
        case .safety: safetySection
        case .dimmedSafety: dimmedSafetySection
        // Among compact rows the stack has no spacing, so the dividers keep their own gap.
        case .settingsDivider: Divider().padding(.bottom, isCompact ? 8 : 0)
        case .closingDivider: Divider().padding(.top, isCompact ? 8 : 0)
        case .lockScreen: lockRow(minHeight: 36)
        case .launchAtLogin: launchRow
        case .checkForUpdates: updatesRow
        case .appearance: appearanceRow
        case .accent: accentRow
        }
    }

    // Off and Run with Lid Closed.
    private var safetySection: some View {
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
    }

    // Keep Screen On: only the timer applies.
    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Timer")
            timerRow
        }
    }

    private var dimmedSafetySection: some View {
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

    private var launchRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(title: "Launch at login", minHeight: 36) {
                SwitchToggle(
                    title: "Launch at login",
                    isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
                )
                .disabled(!launchAtLogin.isInApplications)
            }
            if let notice = launchAtLogin.notice {
                Text(notice.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updatesRow: some View {
        SettingRow(title: "Check for updates", minHeight: 36) {
            SwitchToggle(title: "Check for updates", isOn: $updates.isEnabled)
        }
    }

    private var look: WindowLook {
        WindowLook(style: windowStyle.style, isSystem26OrLater: isSystem26OrLater, reduceTransparency: reduceTransparency)
    }

    private var appearanceRow: some View {
        SettingRow(title: "Appearance", minHeight: 36) {
            Picker("Appearance", selection: $windowStyle.style) {
                ForEach(WindowAppearance.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var accentColor: Color {
        Palette.accent(accent.theme)
    }

    private var accentRow: some View {
        SettingRow(title: "Accent", minHeight: 36) {
            Picker("Accent", selection: $accent.theme) {
                ForEach(AccentTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
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

private extension AccentTheme {
    var title: LocalizedStringKey {
        switch self {
        case .blue: return "Blue"
        case .amber: return "Amber"
        }
    }
}

private extension WindowAppearance {
    var title: LocalizedStringKey {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        }
    }
}

private struct ModeCard: View {
    let mode: Mode
    let isSelected: Bool
    let accent: Color
    let look: WindowLook
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                ModeIconView(mode: mode)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isSelected ? accent : Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(accent))
                        .accessibilityHidden(true)
                }
            }
            // The border is drawn inside the card, so 13 matches the mockup's 12 padding plus a 1 border.
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.cardBackground(look)))
            .overlay(shape.strokeBorder(isSelected ? accent : Palette.cardBorder(look), lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel(Text(mode.title))
        .accessibilityHint(Text(mode.summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension MessageKind {
    var symbol: String {
        switch self {
        case .actionNeeded: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .actionNeeded: return .orange
        case .error: return .red
        case .info: return .secondary
        }
    }

    func background(_ look: WindowLook) -> Color {
        switch self {
        case .actionNeeded: return Color.orange.opacity(0.14)
        case .error: return Color.red.opacity(0.12)
        case .info: return Palette.cardBackground(look)
        }
    }

    func border(_ look: WindowLook) -> Color {
        switch self {
        case .actionNeeded: return Color.orange.opacity(0.45)
        case .error: return Color.red.opacity(0.45)
        case .info: return Palette.cardBorder(look)
        }
    }
}

private struct MessageBanner: View {
    let message: WindowMessage
    let look: WindowLook
    let isActionDisabled: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.kind.symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(message.kind.iconColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(message.text)
                        .font(.system(size: 12))
                    if let hint = message.hint {
                        Text(hint)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                if let actionTitle = message.actionTitle {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(message.source == .helper ? .defaultAction : nil)
                    .disabled(isActionDisabled)
                }
            }
            Spacer(minLength: 0)
        }
        // The border is drawn inside the banner, so 13 matches the mockup's 12 padding plus a 1 border.
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(message.kind.background(look)))
        .overlay(shape.strokeBorder(message.kind.border(look), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct SettingsToggleRow: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                Text("Settings")
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Settings"))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
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
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingRow<Controls: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var minHeight: CGFloat = 44
    @ViewBuilder let controls: Controls

    var body: some View {
        SettingRowLayout(minHeight: minHeight) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                controls
            }
            .fixedSize()
        }
    }
}

/// Lays out a setting row: the controls at their own size on the right, the text in all the
/// width left of them. Sizing and placing use the same widths, so the row is always as tall
/// as the wrapped text, and the text wraps only where it meets the controls.
private struct SettingRowLayout: Layout {
    var minHeight: CGFloat
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = measure(width: proposal.width, subviews: subviews)
        return CGSize(width: measured.width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = measure(width: bounds.width, subviews: subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: measured.textWidth, height: measured.textHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(measured.controls)
        )
    }

    private func measure(width: CGFloat?, subviews: Subviews) -> (width: CGFloat, height: CGFloat, textWidth: CGFloat, textHeight: CGFloat, controls: CGSize) {
        let controls = subviews[1].sizeThatFits(.unspecified)
        let rowWidth = width ?? (subviews[0].sizeThatFits(.unspecified).width + spacing + controls.width)
        let textWidth = max(0, rowWidth - spacing - controls.width)
        let textHeight = subviews[0].sizeThatFits(ProposedViewSize(width: textWidth, height: nil)).height
        let height = max(minHeight, textHeight, controls.height)
        return (rowWidth, height, textWidth, textHeight, controls)
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

/// Reports the height of the view it is the background of.
private struct HeightReader: View {
    @Binding var height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(proxy.size.height) }
                .onChange(of: proxy.size.height) { update($0) }
        }
    }

    private func update(_ value: CGFloat) {
        if value != height {
            height = value
        }
    }
}

/// Watches the window's real frame and screen and reports how tall the content may be.
private struct WindowGeometryReader: NSViewRepresentable {
    @Binding var limit: CGFloat?
    let isScrolling: Bool

    func makeNSView(context: Context) -> WindowGeometryView {
        let view = WindowGeometryView()
        view.onChange = { value in
            if value != limit {
                limit = value
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowGeometryView, context: Context) {
        nsView.isScrolling = isScrolling
    }
}

private final class WindowGeometryView: NSView {
    var onChange: ((CGFloat?) -> Void)?
    var isScrolling = false
    private var fit = WindowFit()
    private var observers: [NSObjectProtocol] = []
    private var loggedHeight: CGFloat?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        fit.reset()
        guard let window else { return }
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, object: Any?, _ handler: @escaping (WindowGeometryView) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                guard let self else { return }
                handler(self)
            })
        }
        // The menu bar window can open on another screen each time, and the Dock can move.
        observe(NSWindow.didBecomeKeyNotification, object: window) { $0.measure(isOpening: true) }
        observe(NSWindow.didResizeNotification, object: window) { $0.measure(isOpening: false) }
        observe(NSWindow.didMoveNotification, object: window) { $0.measure(isOpening: false) }
        observe(NSWindow.didChangeScreenNotification, object: window) { view in
            view.fit.reset()
            view.measure(isOpening: false)
        }
        observe(NSApplication.didChangeScreenParametersNotification, object: nil) { view in
            view.fit.reset()
            view.measure(isOpening: false)
        }
        measure(isOpening: true)
    }

    private func measure(isOpening: Bool) {
        guard let window, let screen = window.screen, let content = window.contentView else { return }
        let geometry = WindowGeometry(
            visibleFrame: screen.visibleFrame,
            windowFrame: window.frame,
            contentHeight: content.frame.height
        )
        let limit = fit.update(geometry)
        if WindowGeometryLog.isEnabled, isOpening || loggedHeight != window.frame.height {
            loggedHeight = window.frame.height
            print(WindowGeometryReport.line(geometry, limit: limit, isScrolling: isScrolling))
            fflush(stdout)
        }
        // Not during a view update: the value goes into SwiftUI state.
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(limit)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
