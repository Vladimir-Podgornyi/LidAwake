import AppKit
import Combine
import LidAwakeCore
import SwiftUI

/// Owns one window of fixed width whose height follows its content, such as What's new: made on
/// first use and kept, so the row brings the same window to the front every time. The page's
/// header and footer stay put; when the whole does not fit, only the middle scrolls.
@MainActor
final class InfoWindowController {
    nonisolated static let width: CGFloat = 520
    /// The tallest the window gets, as a part of the screen without the menu bar and the Dock.
    static let maxScreenShare: CGFloat = 0.85

    private let title: String
    private let content: (_ close: @escaping () -> Void) -> AnyView
    private let layout = InfoPageLayout()
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

    /// The window as it opens, off screen, for `--render-window`. `visibleHeight` stands in for
    /// the height of the screen's visible area.
    func offscreenWindow(appearance: NSAppearance, visibleHeight: CGFloat) -> NSWindow {
        let window = self.window ?? makeWindow()
        self.window = window
        window.appearance = appearance
        fit(window, visibleHeight: visibleHeight)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        return window
    }

    private func close() {
        window?.performClose(nil)
    }

    /// Sets the height to the content's, keeping the top edge where it is. The content fills the
    /// whole window, title bar included.
    private func fit(_ window: NSWindow, visibleHeight: CGFloat? = nil) {
        let full = height(scrollHeight: nil)
        let fixed = height(scrollHeight: 0)
        let screenHeight = visibleHeight ?? (window.screen ?? NSScreen.main)?.visibleFrame.height
        let maxHeight = screenHeight.map { ($0 * Self.maxScreenShare).rounded(.down) }
        let scroll = WindowHeightLimit.scrollHeight(fixedHeight: fixed, contentHeight: full - fixed, maxHeight: maxHeight)
        layout.scrollHeight = scroll
        let height = scroll.map { fixed + $0 } ?? full
        let top = window.isVisible ? window.frame.maxY : window.frame.minY + height
        window.setFrame(
            NSRect(x: window.frame.minX, y: top - height, width: Self.width, height: height),
            display: window.isVisible
        )
    }

    private func height(scrollHeight: CGFloat?) -> CGFloat {
        let page = content({})
            .environment(\.infoScrollHeight, scrollHeight)
            .frame(width: Self.width)
        return NSHostingView(rootView: page).fittingSize.height.rounded(.up)
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
        let host = NSHostingView(rootView: InfoPageHost(layout: layout, page: page))
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

/// The height the middle of a page scrolls in; nil when the whole page fits.
private struct InfoScrollHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var infoScrollHeight: CGFloat? {
        get { self[InfoScrollHeightKey.self] }
        set { self[InfoScrollHeightKey.self] = newValue }
    }
}

@MainActor
private final class InfoPageLayout: ObservableObject {
    @Published var scrollHeight: CGFloat?
}

private struct InfoPageHost: View {
    @ObservedObject var layout: InfoPageLayout
    let page: AnyView

    var body: some View {
        page
            .environment(\.infoScrollHeight, layout.scrollHeight)
            .frame(width: InfoWindowController.width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            // The page leaves room for the window buttons itself.
            .ignoresSafeArea()
    }
}

/// A window page: the header and the footer stay put, the middle scrolls when the window is too
/// short for all of it.
struct InfoPage<Header: View, Middle: View, Footer: View>: View {
    static var sideMargin: CGFloat { 28 }

    @ViewBuilder let header: Header
    @ViewBuilder let middle: Middle
    @ViewBuilder let footer: Footer

    @Environment(\.infoScrollHeight) private var scrollHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) { header }
                .padding(.top, 28)
                .padding(.horizontal, Self.sideMargin)
                .padding(.bottom, scrollHeight == nil ? 20 : 12)
            if let scrollHeight {
                ScrollView(.vertical) {
                    paddedMiddle
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                }
                .frame(height: scrollHeight)
                .overlay(alignment: .top) { Divider() }
                .overlay(alignment: .bottom) { Divider() }
            } else {
                paddedMiddle
            }
            VStack(alignment: .leading, spacing: 0) { footer }
                .padding(.top, 20)
                .padding(.horizontal, Self.sideMargin)
                .padding(.bottom, 20)
        }
        .frame(width: InfoWindowController.width, alignment: .leading)
    }

    private var paddedMiddle: some View {
        VStack(alignment: .leading, spacing: 0) { middle }
            .padding(.horizontal, Self.sideMargin)
            .frame(width: InfoWindowController.width, alignment: .leading)
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
