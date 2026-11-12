import AppKit
import Combine
import SwiftUI

/// Owns one window of fixed width whose height follows its content, such as What's new: made on
/// first use and kept, so the row brings the same window to the front every time. A window
/// taller than the screen scrolls.
@MainActor
final class InfoWindowController {
    nonisolated static let width: CGFloat = 520
    /// Kept free above and below the window on a screen too short for it.
    private static let screenMargin: CGFloat = 40

    private let title: String
    private let content: (_ close: @escaping () -> Void) -> AnyView
    private var window: NSWindow?
    private var activation: NSObjectProtocol?
    private var changes: AnyCancellable?

    /// `changes` tells of anything that may change the content's height while the window is open.
    init<Content: View>(
        title: String,
        changes: AnyPublisher<Void, Never>? = nil,
        @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Content
    ) {
        self.title = title
        self.content = { AnyView(content($0)) }
        self.changes = changes?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let window = self?.window, window.isVisible else { return }
                    self?.fit(window)
                }
            }
    }

    func show() {
        let isNew = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        fit(window)
        if isNew || !window.isVisible {
            window.center()
        }
        // As in the activity log window: the app has no Dock icon, and the window often opens
        // while the app is not active.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            window.orderFrontRegardless()
            makeKeyOnActivation(window)
        }
        // With keyboard navigation on, Space would press the first link right away.
        window.makeFirstResponder(nil)
    }

    private func close() {
        window?.performClose(nil)
    }

    /// Sets the height to the content's, keeping the top edge where it is.
    private func fit(_ window: NSWindow) {
        let measure = NSHostingView(rootView: content({}).frame(width: Self.width))
        var height = measure.fittingSize.height
        if let screen = window.screen ?? NSScreen.main {
            let chrome = window.frame.height - window.contentLayoutRect.height
            height = min(height, screen.visibleFrame.height - chrome - 2 * Self.screenMargin)
        }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: Self.width, height: height.rounded(.up)))
        if window.isVisible {
            window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        }
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

    private func makeWindow() -> NSWindow {
        let window = InfoNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The content starts with the same title, so the bar shows none.
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let page = content { [weak self] in self?.close() }
        let host = NSHostingView(rootView: ViewThatFits(in: .vertical) {
            page
            ScrollView(.vertical) { page }
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor)))
        // The window sets the size; the content only fills it.
        host.sizingOptions = []
        window.contentView = host
        return window
    }
}

/// An app without a main menu gets no Close item, so the window answers ⌘W and Esc itself.
private final class InfoNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

/// The title of a window page and the line under it.
struct InfoPageTitle: View {
    let title: LocalizedStringKey
    var subtitle: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
