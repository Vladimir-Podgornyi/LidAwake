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
    case updates

    var title: Text {
        switch self {
        case .languages: return Text("Six new languages")
        case .movieOnTV: return Text("Movie on a TV")
        case .downloads: return Text("Waits for downloads")
        case .exports: return Text("Waits for video exports")
        case .inABag: return Text("In a Bag")
        case .updates: return Text("Updates in one click")
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
        case .updates: return Text("The Download button opens your purchases, where the new version is ready.")
        }
    }

    var isNew: Bool { self == .inABag }
}

/// The news of one version.
struct WhatsNewRelease {
    let version: String
    /// Top to bottom.
    let features: [WhatsNewFeature]
}

/// Which versions the What's new window shows; set before it opens.
@MainActor
final class WhatsNewChoice: ObservableObject {
    @Published var selection = WhatsNewSelection(versions: [Edition.whatsNewVersion])

    /// The window opens by itself after an update: every version since `lastShown`.
    func sinceLastShown(_ lastShown: String?) {
        selection = .sinceLastShown(history: history, current: Edition.whatsNewVersion, lastShown: lastShown)
    }

    /// Opened from the row.
    func recent() {
        selection = .recent(history: history, current: Edition.whatsNewVersion)
    }

    private var history: [String] { Edition.whatsNewHistory.map(\.version) }

    static func releases(_ selection: WhatsNewSelection) -> [WhatsNewRelease] {
        selection.versions.compactMap { version in
            Edition.whatsNewHistory.first { $0.version == version }
        }
    }
}

/// The What's new window: the news of the versions chosen and, where LidAwake Pro is offered,
/// what only Pro has and the running discount.
struct WhatsNewScreen: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var accent: AccentPreference
    @ObservedObject var choice: WhatsNewChoice
    let close: () -> Void

    var body: some View {
        WhatsNewContent(
            releases: WhatsNewChoice.releases(choice.selection),
            earlierCount: choice.selection.earlierCount,
            sections: WhatsNewSections(showsPro: Edition.showsProOffer, offer: updates.offer),
            accent: Palette.accent(accent.theme),
            onAccent: Palette.onAccentText(accent.theme),
            language: Bundle.main.preferredLocalizations.first,
            close: close
        )
    }
}

struct WhatsNewContent: View {
    /// Newest first.
    let releases: [WhatsNewRelease]
    var earlierCount = 0
    let sections: WhatsNewSections
    let accent: Color
    /// The text of the New badge.
    let onAccent: Color
    let language: String?
    /// Every picture on its last frame, as with Reduce motion.
    var isStill = false
    let close: () -> Void

    var body: some View {
        InfoPage {
            // A single version is named under the title; several each get their own heading.
            InfoPageTitle(
                title: "What's new in \(Edition.name)",
                subtitle: releases.count == 1 ? Text("Version \(releases[0].version)") : nil
            )
        } middle: {
            ForEach(Array(releases.enumerated()), id: \.element.version) { index, release in
                if releases.count > 1 {
                    Text("Version \(release.version)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.readableSecondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, index == 0 ? 0 : 22)
                        .padding(.bottom, 10)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(release.features, id: \.self) { feature in
                        WhatsNewRow(feature: feature, accent: accent, isStill: isStill)
                    }
                }
            }
            if earlierCount > 0 {
                Text("and \(earlierCount) earlier updates")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.readableSecondary)
                    .padding(.top, 16)
            }
            if sections.showsProFeatures {
                Divider()
                    .padding(.vertical, 20)
                Text("Only in LidAwake Pro \(Edition.proVersion)")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.readableSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
                ProTiles(features: Edition.proFeatures, accent: accent, onAccent: onAccent, isStill: isStill)
            }
        } footer: {
            if let offer = sections.discount {
                WhatsNewDiscount(offer: offer, language: language, accent: accent)
                    .padding(.bottom, 20)
            }
            HStack {
                Spacer()
                Button(action: close) {
                    Text("Continue")
                        .frame(minWidth: 72)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .tint(accent)
    }
}

private struct WhatsNewRow: View {
    let feature: WhatsNewFeature
    let accent: Color
    let isStill: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            FeaturePicture(feature: feature, accent: accent, isStill: isStill, isCompact: true)
                .frame(width: 96, height: 64)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.pictureBackground))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    feature.title
                        .font(.system(size: 13, weight: .semibold))
                    if Edition.newFeatures.contains(feature) {
                        Text("New")
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(accent, lineWidth: 1))
                    }
                }
                feature.detail
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Pro features two to a row; the tiles of a row are as tall as the tallest.
private struct ProTiles: View {
    static let gap: CGFloat = 10

    let features: [WhatsNewFeature]
    let accent: Color
    let onAccent: Color
    let isStill: Bool

    var body: some View {
        let rows = stride(from: 0, to: features.count, by: 2).map { Array(features[$0..<min($0 + 2, features.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { feature in
                        WhatsNewTile(feature: feature, accent: accent, onAccent: onAccent, isStill: isStill)
                    }
                    if row.count == 1 {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

private struct WhatsNewTile: View {
    let feature: WhatsNewFeature
    let accent: Color
    let onAccent: Color
    let isStill: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            FeaturePicture(feature: feature, accent: accent, isStill: isStill)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(Palette.pictureBackground)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    feature.title
                        .font(.system(size: 13, weight: .bold))
                    if feature.isNew {
                        Text("New")
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(accent))
                    }
                }
                feature.detail
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.tileBackground)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.tileBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
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
                        .foregroundStyle(Palette.readableSecondary)
                    Text(verbatim: newPrice)
                        .font(.system(size: 13, weight: .semibold))
                    Text(terms)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.readableSecondary)
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
    /// The small picture of a row rather than the wide one of a tile.
    var isCompact = false

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
        case .languages: GreetingPicture(time: time)
        case .movieOnTV: MovieOnTVPicture(time: time, accent: accent)
        case .downloads: SleepAfterPicture(time: time, symbol: "arrow.down", symbolColor: accent, accent: accent)
        case .exports: SleepAfterPicture(time: time, symbol: "film", symbolColor: .primary, accent: accent)
        case .inABag: BagPicture(time: time, isCompact: isCompact)
        case .updates: UpdatePicture(time: time, accent: accent)
        }
    }
}

/// How long one round of a picture lasts, and where it stands when it does not move.
private struct FeatureLoop {
    let period: Double
    let stillTime: Double
    /// The words fade out and in themselves; the other pictures fade out at the end of a round
    /// and in at the start of the next, so they do not jump back.
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
        case .updates:
            period = 4
            stillTime = 3.5
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

/// One word a second: each fades out before the next fades in, so two are never seen at once.
private struct GreetingPicture: View {
    static let words = ["Hello", "こんにちは", "Bonjour", "Hola", "Olá", "안녕하세요", "Ciao"]

    let time: Double

    var body: some View {
        let index = Int(time) % Self.words.count
        let part = time - floor(time)
        word(Self.words[index])
            .opacity(Ease.step(part, from: 0, to: 0.15) * (1 - Ease.step(part, from: 0.85, to: 1)))
    }

    private func word(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
    }
}

/// A laptop seen from the front; the screen shrinks down to the hinge as the lid closes.
private struct LaptopShape: View {
    /// 1 open, 0 shut.
    let open: Double
    var width: CGFloat = 46

    var body: some View {
        let screenHeight = width * 0.56
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(Color.primary, lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Palette.deviceScreen))
                .frame(width: width * 0.82, height: screenHeight)
                .scaleEffect(x: 1, y: max(open, 0.07), anchor: .bottom)
                .frame(height: screenHeight, alignment: .bottom)
            Capsule()
                .fill(Color.primary)
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
                    .strokeBorder(Color.primary, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Palette.deviceScreen))
                    .frame(width: 66, height: 34)
                    .overlay(alignment: .bottom) {
                        ProgressTrack(value: time / 6, color: accent, track: Color.white.opacity(0.25))
                            .frame(width: 50, height: 3)
                            .padding(.bottom, 6)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .offset(y: -3)
                    }
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 22, height: 2)
            }
            LaptopShape(open: lid, width: 36)
        }
    }
}

/// Work goes on while the bar fills; once it is full, the Mac sleeps.
private struct SleepAfterPicture: View {
    let time: Double
    let symbol: String
    let symbolColor: Color
    let accent: Color

    var body: some View {
        let moon = Ease.step(time, from: 3.8, to: 4.4)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 24)
            ProgressTrack(value: Ease.step(time, from: 0.3, to: 3.5), color: Palette.waitBar)
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
    var isCompact = false

    var body: some View {
        let lid = 1 - Ease.step(time, from: 0.5, to: 1.5)
        let bag = Ease.step(time, from: 1.7, to: 2.9)
        let heat = 0.7 * Ease.step(time, from: 3.1, to: 5.2)
        let scale: CGFloat = isCompact ? 0.72 : 1
        HStack(spacing: isCompact ? 6 : 14) {
            ZStack(alignment: .bottom) {
                LaptopShape(open: lid, width: 40 * scale)
                    .padding(.bottom, 8 * scale)
                BagShape()
                    .frame(width: 58 * scale, height: 40 * scale)
                    .offset(y: (1 - bag) * 60 * scale)
            }
            .frame(width: 62 * scale, height: 58 * scale, alignment: .bottom)
            .clipped()
            HStack(spacing: isCompact ? 3 : 5) {
                Image(systemName: "thermometer")
                    .font(.system(size: isCompact ? 12 : 15))
                    .foregroundStyle(.primary)
                ProgressTrack(value: heat, color: Palette.waitBar)
                    .frame(width: isCompact ? 20 : 64, height: isCompact ? 5 : 6)
            }
        }
    }
}

/// The Download button is pressed, the new version comes down, and a green check shows it is there.
private struct UpdatePicture: View {
    let time: Double
    let accent: Color

    var body: some View {
        let press = Ease.step(time, from: 0.4, to: 0.55) * (1 - Ease.step(time, from: 0.6, to: 0.8))
        let arrow = Ease.step(time, from: 0.8, to: 1.2)
        let check = Ease.step(time, from: 2.8, to: 3.1)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        VStack(spacing: 8) {
            // The same word as on the update banner's button.
            Text("Download")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: 60)
                .foregroundStyle(accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(shape.fill(accent.opacity(0.12 + 0.18 * press)))
                .overlay(shape.strokeBorder(accent, lineWidth: 1))
                .scaleEffect(1 - 0.08 * press)
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 12)
                    .opacity(arrow)
                    .offset(y: -6 * (1 - arrow))
                ProgressTrack(value: Ease.step(time, from: 1.2, to: 2.7), color: accent)
                    .frame(width: 44, height: 5)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .frame(width: 14)
                    .opacity(check)
                    .scaleEffect(0.6 + 0.4 * check)
            }
        }
    }
}

private struct BagShape: View {
    var body: some View {
        let body = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .top) {
            HandleShape()
                .stroke(Color.primary, lineWidth: 2)
                .frame(width: 22, height: 10)
            body
                .fill(Palette.pictureBackground)
                .overlay(body.fill(Color.primary.opacity(0.08)))
                .overlay(body.strokeBorder(Color.primary, lineWidth: 1.5))
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
    var track = Color.primary.opacity(0.15)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
    }
}
