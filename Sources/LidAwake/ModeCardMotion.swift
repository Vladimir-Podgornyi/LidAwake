import AppKit
import SwiftUI

/// Lays its content out at the content's own height times `progress` and leaves the rest out,
/// so a part of a mode card unfolds and folds frame by frame and the window's height follows.
private struct RevealLayout: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: proposal.width, height: nil)
        )
    }
}

extension View {
    /// The view at its full height when `isShown`, folded to no height otherwise. Spacing above
    /// it belongs inside, so that it folds away too.
    func unfolded(_ isShown: Bool) -> some View {
        RevealLayout(progress: isShown ? 1 : 0) {
            opacity(isShown ? 1 : 0)
        }
        .clipShape(BelowCut())
        .accessibilityHidden(!isShown)
    }

    /// Text beside the selected card's check mark, as narrow while the check mark is not there,
    /// so that it does not wrap anew as the card folds or unfolds.
    func keepingWidthOfCheckmark(isShown: Bool) -> some View {
        padding(.trailing, isShown ? 0 : 12 + 18)
            .transaction { $0.animation = nil }
    }

    /// The card draws its own focus ring, so the system one is left out.
    @ViewBuilder
    func withoutSystemFocusRing() -> some View {
        if #available(macOS 14, *) {
            focusEffectDisabled()
        } else {
            background(SystemFocusRingHider())
        }
    }

    /// A thin ring in the accent color 2 points outside a mode card, for a card that has the
    /// keyboard focus but is not the selected one; the selected card's border already marks it.
    func cardFocusRing(_ isShown: Bool, color: Color) -> some View {
        overlay {
            if isShown {
                RoundedRectangle(cornerRadius: 10 + CardFocusRingMetrics.outset, style: .continuous)
                    .strokeBorder(color, lineWidth: CardFocusRingMetrics.lineWidth)
                    .padding(-CardFocusRingMetrics.outset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Cuts off only what reaches below the folded part; content drawn up into the space above it,
/// by a negative padding, stays.
private struct BelowCut: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - rect.height - 100, width: rect.width, height: 2 * rect.height + 100))
    }
}

private enum CardFocusRingMetrics {
    static let gap: CGFloat = 2
    static let lineWidth: CGFloat = 1.5
    static var outset: CGFloat { gap + lineWidth }
}

/// macOS 13 has no way to turn off the focus ring of a SwiftUI control. SwiftUI draws the ring
/// as a view of its own over the hosting view, as large as the control, and makes such views
/// anew as the window changes. The ones that lie on the card this view is behind are hidden when
/// the window opens, when the focus moves and each time one of them gets its place.
private struct SystemFocusRingHider: NSViewRepresentable {
    func makeNSView(context: Context) -> SystemFocusRingHiderView {
        SystemFocusRingHiderView()
    }

    func updateNSView(_ nsView: SystemFocusRingHiderView, context: Context) {}
}

private final class SystemFocusRingHiderView: NSView {
    private var observer: NSObjectProtocol?
    private var responderObservation: NSKeyValueObservation?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        responderObservation = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let ring = note.object as? NSView else { return }
            MainActor.assumeIsolated { self?.hideIfOnCard(ring) }
        }
        // The ring views are made after the responder changes and after the window is laid out.
        responderObservation = window.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { self?.hideRings() }
        }
        DispatchQueue.main.async { [weak self] in self?.hideRings() }
    }

    private func hideRings() {
        guard let window else { return }
        var views: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = views.popLast() {
            hideIfOnCard(view)
            views += view.subviews
        }
    }

    private func hideIfOnCard(_ ring: NSView) {
        guard !ring.isHidden, ring.window === window, let parent = ring.superview,
              String(describing: type(of: ring)).hasSuffix("_FocusRingView")
        else { return }
        let card = convert(bounds, to: parent)
        // The card's button may be only its upper part. The timer choice inside a card has a ring
        // of its own, much narrower; it stays.
        if card.insetBy(dx: -6, dy: -6).contains(ring.frame), ring.frame.width > card.width - 12 {
            ring.isHidden = true
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
