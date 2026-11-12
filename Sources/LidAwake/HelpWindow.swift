import AppKit
import LidAwakeCore
import SwiftUI

/// The How to use LidAwake window: the three steps, the warning about bags and the links of
/// this edition.
struct HelpScreen: View {
    @ObservedObject var accent: AccentPreference
    let close: () -> Void

    var body: some View {
        HelpContent(
            accent: Palette.accent(accent.theme),
            onAccent: Palette.onAccent(accent.theme),
            version: AppVersion.installedText,
            language: Bundle.main.preferredLocalizations.first,
            close: close
        )
    }
}

struct HelpContent: View {
    let accent: Color
    let onAccent: Color
    let version: String
    let language: String?
    let close: () -> Void

    var body: some View {
        InfoPage {
            InfoPageTitle(title: "How to use LidAwake")
        } middle: {
            VStack(alignment: .leading, spacing: 16) {
                HelpStep(
                    number: 1,
                    title: "Pick a mode",
                    text: "Keep Screen On when you step away from the desk. Run with Lid Closed when the Mac should keep working with the lid shut. Only one mode is on at a time; Off brings normal sleep back.",
                    accent: accent,
                    onAccent: onAccent
                )
                HelpStep(
                    number: 2,
                    title: "Allow the helper once",
                    text: "The first time you choose Run with Lid Closed, allow LidAwake in System Settings › General › Login Items & Extensions. No password is needed.",
                    accent: accent,
                    onAccent: onAccent
                )
                HelpStep(
                    number: 3,
                    title: "Let it end by itself",
                    text: "In Settings, Sleep when idle lets the Mac sleep once the work is done, and Turn off after ends the mode after a set time. With Sleep when idle on, adding the first watched app sets Turn off after to 4 hours, so a stuck app can't keep the Mac awake forever. The mode also stops when the Mac gets hot or the battery runs low.",
                    accent: accent,
                    onAccent: onAccent
                )
            }
            BagWarning()
                .padding(.top, 20)
        } footer: {
            Divider()
                .padding(.bottom, 14)
            // Without room the copyright goes under the name; the links and the button stay put.
            ViewThatFits(in: .horizontal) {
                footerRow(credit: "\(Self.versionName(version)) · \(Self.copyright)")
                footerRow(credit: "\(Self.versionName(version))\n\(Self.copyright)")
            }
        }
        .tint(accent)
    }

    static let copyright = "© 2026 Vladimir Podgornyi"

    static func versionName(_ version: String) -> String {
        version.isEmpty ? Edition.name : "\(Edition.name) \(version)"
    }

    private func footerRow(credit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(verbatim: credit)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            ForEach(Edition.helpLinks, id: \.self) { link in
                Link(destination: link.url(language: language)) {
                    Text(link.title)
                        .font(.system(size: 12))
                }
                .foregroundStyle(accent)
                .fixedSize()
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Text("Done")
                    .frame(minWidth: 72)
            }
            .keyboardShortcut(.defaultAction)
            .fixedSize()
        }
    }
}

private extension ProjectLink {
    var title: LocalizedStringKey {
        switch self {
        case .website: return "Website"
        case .sourceCode: return "Source code"
        }
    }
}

private struct HelpStep: View {
    let number: Int
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let accent: Color
    let onAccent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BagWarning: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let yellow = Color(nsColor: .systemYellow)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Avoid packing a running Mac in a closed bag")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("A closed laptop in a bag cools poorly. The protections reduce the risk; they do not remove it. If you must carry it running, prefer a short session and keep an eye on the temperature. You use LidAwake at your own risk.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(yellow.opacity(0.16)))
        .overlay(shape.strokeBorder(yellow.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
