import AppKit
import LidAwakeCore
import SwiftUI

/// A feature the What's new window shows, with its moving picture.
enum WhatsNewFeature: Hashable {
    case languages
    case movieOnTV
    case downloads
    case exports
    case inABag

    var title: Text {
        switch self {
        case .languages: return Text("Six new languages")
        case .movieOnTV: return Text("Movie on a TV")
        case .downloads: return Text("Waits for downloads")
        case .exports: return Text("Waits for video exports")
        case .inABag: return Text("In a Bag")
        }
    }

    var detail: Text {
        switch self {
        // Each language under its own name.
        case .languages: return Text(verbatim: "日本語, Français, Español, Português (Brasil), 한국어, Italiano.")
        case .movieOnTV: return Text("Close the lid and the movie keeps playing on the TV.")
        case .downloads: return Text("Stays awake until a big download is done, then sleeps.")
        case .exports: return Text("Stays awake while a video renders, then sleeps.")
        case .inABag: return Text("One switch with stricter protections for a Mac in a bag.")
        }
    }

    var isNew: Bool { self == .inABag }
}

/// The What's new window: the news of this build and, where LidAwake Pro is offered, what only
/// Pro has and the running discount.
struct WhatsNewScreen: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var accent: AccentPreference
    let close: () -> Void
    var isStill = false

    var body: some View {
        WhatsNewContent(
            sections: WhatsNewSections(showsPro: Edition.showsProOffer, offer: updates.offer),
            accent: Palette.accent(accent.theme),
            language: Bundle.main.preferredLocalizations.first,
            isStill: isStill,
            close: close
        )
    }
}

struct WhatsNewContent: View {
    let sections: WhatsNewSections
    let accent: Color
    let language: String?
    /// Every picture on its last frame, as with Reduce motion.
    var isStill = false
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoPageTitle(
                title: "What's new in LidAwake",
                subtitle: Text("Version \(Edition.whatsNewVersion)")
            )
            .padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Edition.whatsNew, id: \.self) { feature in
                    WhatsNewRow(feature: feature, accent: accent, isStill: isStill)
                }
            }
            if sections.showsProFeatures {
                Divider()
                    .padding(.vertical, 20)
                Text("Only in LidAwake Pro \(Edition.proVersion)")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), alignment: .top)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(Edition.proFeatures, id: \.self) { feature in
                        WhatsNewTile(feature: feature, accent: accent, isStill: isStill)
                    }
                }
            }
            if let offer = sections.discount {
                WhatsNewDiscount(offer: offer, language: language, accent: accent)
                    .padding(.top, 20)
            }
            HStack {
                Spacer()
                Button(action: close) {
                    Text("Continue")
                        .frame(minWidth: 72)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .frame(width: InfoWindowController.width, alignment: .leading)
        .tint(accent)
    }
}

private struct WhatsNewRow: View {
    let feature: WhatsNewFeature
    let accent: Color
    let isStill: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FeaturePicture(feature: feature, accent: accent, isStill: isStill)
                .frame(width: 96, height: 64)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.10)))
            VStack(alignment: .leading, spacing: 3) {
                feature.title
                    .font(.system(size: 13, weight: .semibold))
                feature.detail
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WhatsNewTile: View {
    let feature: WhatsNewFeature
    let accent: Color
    let isStill: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeaturePicture(feature: feature, accent: accent, isStill: isStill)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    feature.title
                        .font(.system(size: 13, weight: .semibold))
                    if feature.isNew {
                        Text("New")
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(accent))
                    }
                }
                feature.detail
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The discount on LidAwake Pro, as the card in the menu bar window shows it. Only the numbers,
/// the date and the link come from the update file.
private struct WhatsNewDiscount: View {
    let offer: UpdateOffer
    let language: String?
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("−\(offer.percent)% on LidAwake Pro")
                    .font(.system(size: 13, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: oldPrice)
                        .font(.system(size: 11))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text(verbatim: newPrice)
                        .font(.system(size: 13, weight: .semibold))
                    Text(terms)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Get Pro") {
                NSWorkspace.shared.open(offer.url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(accent.opacity(0.10)))
        .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1))
    }

    private var oldPrice: String { OfferFormat.price(offer.priceAmount, language: language) }
    private var newPrice: String { OfferFormat.price(offer.saleAmount, language: language) }

    private var terms: LocalizedStringKey {
        guard let day = offer.lastDay().map({ OfferFormat.day($0, language: language) }) else { return "one-time" }
        return "one-time · until \(day)"
    }
}

/// The moving picture of a feature, looping for ever. With Reduce motion on it stands still on
/// its last frame.
struct FeaturePicture: View {
    let feature: WhatsNewFeature
    let accent: Color
    var isStill = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = isStill || reduceMotion
        let loop = FeatureLoop(feature)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let time = still
                ? loop.stillTime
                : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop.period)
            picture(at: time)
                .opacity(loop.fade(at: time))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func picture(at time: Double) -> some View {
        switch feature {
        case .languages: GreetingPicture(time: time, accent: accent)
        case .movieOnTV: MovieOnTVPicture(time: time, accent: accent)
        case .downloads: SleepAfterPicture(time: time, symbol: "arrow.down", accent: accent, bar: accent)
        case .exports: SleepAfterPicture(time: time, symbol: "film", accent: accent, bar: Palette.accent(.amber))
        case .inABag: BagPicture(time: time, accent: accent)
        }
    }
}

/// How long one round of a picture lasts, and where it stands when it does not move.
private struct FeatureLoop {
    let period: Double
    let stillTime: Double
    /// The words fade into each other themselves; the other pictures fade out at the end of a
    /// round and in at the start of the next, so they do not jump back.
    let fadesAround: Bool

    init(_ feature: WhatsNewFeature) {
        switch feature {
        case .languages:
            period = Double(GreetingPicture.words.count)
            stillTime = period - 0.5
            fadesAround = false
        case .movieOnTV, .downloads, .exports:
            period = 6
            stillTime = 5.4
            fadesAround = true
        case .inABag:
            period = 7
            stillTime = 6.4
            fadesAround = true
        }
    }

    func fade(at time: Double) -> Double {
        guard fadesAround else { return 1 }
        return Ease.step(time, from: 0, to: 0.3) * (1 - Ease.step(time, from: period - 0.4, to: period))
    }
}

private enum Ease {
    /// 0 before `from`, 1 after `to`, smooth in between.
    static func step(_ time: Double, from: Double, to: Double) -> Double {
        let x = min(max((time - from) / (to - from), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// One word a second, each fading into the next.
private struct GreetingPicture: View {
    static let words = ["Hello", "こんにちは", "Bonjour", "Hola", "Olá", "안녕하세요", "Ciao"]

    let time: Double
    let accent: Color

    var body: some View {
        let index = Int(time) % Self.words.count
        let blend = Ease.step(time - floor(time), from: 0.75, to: 1)
        ZStack {
            word(Self.words[index]).opacity(1 - blend)
            word(Self.words[(index + 1) % Self.words.count]).opacity(blend)
        }
    }

    private func word(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
    }
}

/// A laptop seen from the front; the screen shrinks down to the hinge as the lid closes.
private struct LaptopShape: View {
    /// 1 open, 0 shut.
    let open: Double
    let accent: Color
    var width: CGFloat = 46

    var body: some View {
        let screenHeight = width * 0.56
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.65), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(accent.opacity(0.18)))
                .frame(width: width * 0.82, height: screenHeight)
                .scaleEffect(x: 1, y: max(open, 0.07), anchor: .bottom)
                .frame(height: screenHeight, alignment: .bottom)
            Capsule()
                .fill(Color.primary.opacity(0.65))
                .frame(width: width, height: 3)
        }
    }
}

/// The movie keeps playing on the TV while the laptop below closes.
private struct MovieOnTVPicture: View {
    let time: Double
    let accent: Color

    var body: some View {
        let lid = 1 - Ease.step(time, from: 1.5, to: 2.7)
        VStack(spacing: 4) {
            VStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.65), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(accent.opacity(0.18)))
                    .frame(width: 66, height: 34)
                    .overlay(alignment: .bottom) {
                        ProgressTrack(value: time / 6, color: accent)
                            .frame(width: 50, height: 3)
                            .padding(.bottom, 6)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(accent)
                            .offset(y: -3)
                    }
                Capsule()
                    .fill(Color.primary.opacity(0.65))
                    .frame(width: 22, height: 2)
            }
            LaptopShape(open: lid, accent: accent, width: 36)
        }
    }
}

/// Work goes on while the bar fills; once it is full, the Mac sleeps.
private struct SleepAfterPicture: View {
    let time: Double
    let symbol: String
    let accent: Color
    let bar: Color

    var body: some View {
        let moon = Ease.step(time, from: 3.8, to: 4.4)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24)
            ProgressTrack(value: Ease.step(time, from: 0.3, to: 3.5), color: bar)
                .frame(width: 92, height: 6)
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(width: 20)
                .opacity(moon)
                .scaleEffect(0.6 + 0.4 * moon)
        }
    }
}

/// The lid closes, a bag comes up over the laptop, and the heat inside rises. The bar keeps its
/// width; only the part filled grows.
private struct BagPicture: View {
    let time: Double
    let accent: Color

    var body: some View {
        let lid = 1 - Ease.step(time, from: 0.5, to: 1.5)
        let bag = Ease.step(time, from: 1.7, to: 2.9)
        let heat = 0.7 * Ease.step(time, from: 3.1, to: 5.2)
        HStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                LaptopShape(open: lid, accent: accent, width: 40)
                    .padding(.bottom, 8)
                BagShape(accent: accent)
                    .frame(width: 58, height: 40)
                    .offset(y: (1 - bag) * 60)
            }
            .frame(width: 62, height: 58, alignment: .bottom)
            .clipped()
            HStack(spacing: 5) {
                Image(systemName: "thermometer")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
                ProgressTrack(value: heat, color: accent)
                    .frame(width: 64, height: 6)
            }
        }
    }
}

private struct BagShape: View {
    let accent: Color

    var body: some View {
        let body = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .top) {
            HandleShape()
                .stroke(Color.primary.opacity(0.65), lineWidth: 2)
                .frame(width: 22, height: 10)
            body
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(body.fill(accent.opacity(0.22)))
                .overlay(body.strokeBorder(Color.primary.opacity(0.65), lineWidth: 1.5))
                .padding(.top, 8)
        }
    }
}

private struct HandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 4))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 4), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// A bar of fixed size, filled from the left.
private struct ProgressTrack: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
    }
}
