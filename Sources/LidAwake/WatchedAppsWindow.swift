import AppKit
import LidAwakeCore
import LidAwakeShared
import SwiftUI
import UniformTypeIdentifiers

/// Owns the one Watched Apps window, made on first use and kept, like the activity log window.
@MainActor
final class WatchedAppsWindowController {
    nonisolated static let width: CGFloat = 440
    nonisolated static let initialHeight: CGFloat = 520
    nonisolated static let minimumHeight: CGFloat = 320

    private let preferences: SafetyPreferences
    private let accent: AccentPreference
    private let monitor = WatchedAppsMonitor()
    private var window: NSWindow?
    private var activation: NSObjectProtocol?
    private var closing: NSObjectProtocol?

    init(preferences: SafetyPreferences, accent: AccentPreference) {
        self.preferences = preferences
        self.accent = accent
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        monitor.start()
        // As in the activity log window: the app has no Dock icon, and the row is often pressed
        // while the app is not active.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            window.orderFrontRegardless()
            makeKeyOnActivation(window)
        }
        // With keyboard navigation on, the window would put the first switch in focus, and Space
        // would change the choice right away. The window keeps the keys; Tab moves to the switches.
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeFirstResponder(nil)
    }

    private func close() {
        window?.performClose(nil)
    }

    private func makeKeyOnActivation(_ window: NSWindow) {
        stopWaitingForActivation()
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                self?.stopWaitingForActivation()
                guard let window, window.isVisible else { return }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func stopWaitingForActivation() {
        if let activation {
            NotificationCenter.default.removeObserver(activation)
        }
        activation = nil
    }

    private func addOtherApp() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let self, let url = panel.url, url.pathExtension == "app" else { return }
                self.preferences.watchedAppPaths = WatchedAppSelection.setting(
                    url.path,
                    isOn: true,
                    in: self.preferences.watchedAppPaths
                )
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = WatchedAppsNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Watched Apps")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Self.width, height: Self.minimumHeight)
        window.contentMaxSize = NSSize(width: Self.width, height: .greatestFiniteMagnitude)
        let host = NSHostingView(rootView: WatchedAppsScreen(
            preferences: preferences,
            accent: accent,
            monitor: monitor,
            addOtherApp: { [weak self] in self?.addOtherApp() },
            done: { [weak self] in self?.close() }
        ))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: Self.width, height: Self.initialHeight))
        window.center()
        // The processes are read only while the window is open.
        closing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.monitor.stop()
            }
        }
        return window
    }
}

/// An app without a main menu gets no Close item, so the window answers ⌘W and Esc itself.
private final class WatchedAppsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }
}

/// The running apps and whether what they started is working, read every few seconds while the
/// window is open. The app reads its own processes; the helper is not asked.
@MainActor
final class WatchedAppsMonitor: ObservableObject {
    static let interval: TimeInterval = 3

    @Published private(set) var running: [RunningApp] = []
    /// Paths of the open apps whose started programs are working; nil until two readings are in.
    @Published private(set) var busy: Set<String>?

    private var activity = WatchedAppActivity()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Tells a reading that comes back after the window closed from a current one.
    private var generation = 0

    func start() {
        guard timer == nil else { return }
        generation += 1
        refreshApps()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshApps() }
            })
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        generation += 1
        activity = WatchedAppActivity()
        busy = nil
    }

    private func refreshApps() {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard let url = app.bundleURL else { return nil }
            return RunningApp(
                path: url.path,
                name: app.localizedName ?? "",
                bundleIdentifier: app.bundleIdentifier,
                isRegular: app.activationPolicy == .regular
            )
        }
        if apps != running {
            running = apps
        }
    }

    private func sample() {
        refreshApps()
        let paths = running.filter(\.isRegular).map(\.path)
        let current = generation
        Task.detached(priority: .utility) {
            let processes = UserProcessSnapshots.read()
            let time = ProcessInfo.processInfo.systemUptime
            await MainActor.run { [weak self] in
                guard let self, self.generation == current, let processes else { return }
                let busy = self.activity.add(processes, at: time, appPaths: paths)
                if let busy, busy != self.busy {
                    self.busy = busy
                }
            }
        }
    }
}

enum AppDisplayName {
    /// The name Finder shows, without `.app`.
    static func of(_ path: String) -> String {
        let shown = FileManager.default.displayName(atPath: path)
        let name = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
        return name.isEmpty ? WatchedApps.name(ofAppAt: path) : name
    }

    static func icon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

struct WatchedAppsScreen: View {
    @ObservedObject var preferences: SafetyPreferences
    @ObservedObject var accent: AccentPreference
    @ObservedObject var monitor: WatchedAppsMonitor
    let addOtherApp: () -> Void
    let done: () -> Void

    var body: some View {
        WatchedAppsContent(
            list: WatchedAppList.make(
                running: monitor.running,
                watched: preferences.watchedAppPaths,
                ownBundleIdentifier: Bundle.main.bundleIdentifier,
                ownPath: Bundle.main.bundleURL.path,
                name: AppDisplayName.of
            ),
            busy: monitor.busy,
            canAdd: WatchedAppSelection.canAdd(to: preferences.watchedAppPaths),
            accent: Palette.accent(accent.theme),
            icon: AppDisplayName.icon,
            setWatched: { path, isOn in
                preferences.watchedAppPaths = WatchedAppSelection.setting(path, isOn: isOn, in: preferences.watchedAppPaths)
            },
            addOtherApp: addOtherApp,
            done: done
        )
    }
}

struct WatchedAppsContent: View {
    let list: WatchedAppList
    let busy: Set<String>?
    let canAdd: Bool
    let accent: Color
    let icon: (String) -> NSImage
    let setWatched: (String, Bool) -> Void
    let addOtherApp: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("While a watched app runs programs it started, such as a coding agent, a build or a script, Sleep when idle keeps counting it as work. Typing in the app and its own windows do not count.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    header("Open now")
                    ForEach(list.open) { entry in
                        row(entry, state: openState(entry))
                    }
                    if !list.notOpen.isEmpty {
                        header("Watched, not open")
                        ForEach(list.notOpen) { entry in
                            row(entry, state: .notOpen)
                                .opacity(0.6)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 12) {
                Button("Add Other App…", action: addOtherApp)
                    .disabled(!canAdd)
                Spacer(minLength: 0)
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: WatchedAppsWindowController.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private enum State {
        case working
        case quiet
        case notOpen
        /// Not measured yet.
        case unknown
    }

    private func openState(_ entry: WatchedAppEntry) -> State {
        guard let busy else { return .unknown }
        return busy.contains(entry.path) ? .working : .quiet
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ entry: WatchedAppEntry, state: State) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(entry.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                stateLine(state)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Toggle(
                entry.name,
                isOn: Binding(get: { entry.isWatched }, set: { setWatched(entry.path, $0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!entry.isWatched && !canAdd)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func stateLine(_ state: State) -> some View {
        switch state {
        case .working:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 3 }
                    .accessibilityHidden(true)
                stateText("Started programs are working now")
            }
        case .quiet:
            stateText("Nothing running")
        case .notOpen:
            stateText("Not open")
        case .unknown:
            EmptyView()
        }
    }

    private func stateText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
