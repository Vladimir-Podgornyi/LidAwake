import Foundation

/// When the What's new window opens by itself: on the first launch of a build whose news differ
/// from the ones last shown, the very first launch of the app included. Once for each version.
public struct WhatsNewLaunch {
    public static let shownVersionKey = "whatsNewShownVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The version the window last opened for; nil before the very first time.
    public var lastShownVersion: String? {
        defaults.string(forKey: Self.shownVersionKey)
    }

    /// `version` is the version the news of this build describe.
    public func opensByItself(version: String) -> Bool {
        defaults.string(forKey: Self.shownVersionKey) != version
    }

    public func markShown(version: String) {
        defaults.set(version, forKey: Self.shownVersionKey)
    }
}

/// The versions whose news the What's new window shows, newest first.
public struct WhatsNewSelection: Equatable {
    public static let maxVersions = 3

    public let versions: [String]
    /// Missed versions beyond `maxVersions`; the window only names how many.
    public let earlierCount: Int

    public init(versions: [String], earlierCount: Int = 0) {
        self.versions = versions
        self.earlierCount = earlierCount
    }

    /// The window opens by itself: every version of `history` after `lastShown` up to `current`.
    /// Without a version shown before, only `current`.
    public static func sinceLastShown(history: [String], current: String, lastShown: String?) -> WhatsNewSelection {
        guard let now = AppVersion(current),
              let last = lastShown.flatMap(AppVersion.init),
              last < now else {
            return WhatsNewSelection(versions: [current])
        }
        var missed = newestFirst(history.filter { version in
            AppVersion(version).map { last < $0 && $0 <= now } ?? false
        })
        if !missed.contains(where: { AppVersion($0) == now }) {
            missed.insert(current, at: 0)
        }
        return WhatsNewSelection(
            versions: Array(missed.prefix(maxVersions)),
            earlierCount: max(0, missed.count - maxVersions)
        )
    }

    /// Opened from the row: `current` and the versions just before it.
    public static func recent(history: [String], current: String) -> WhatsNewSelection {
        guard let now = AppVersion(current) else { return WhatsNewSelection(versions: [current]) }
        var versions = newestFirst(history.filter { version in
            AppVersion(version).map { $0 < now } ?? false
        })
        versions.insert(current, at: 0)
        return WhatsNewSelection(versions: Array(versions.prefix(maxVersions)))
    }

    private static func newestFirst(_ versions: [String]) -> [String] {
        var seen: [AppVersion] = []
        return versions
            .compactMap { text in AppVersion(text).map { (text, $0) } }
            .sorted { $0.1 > $1.1 }
            .filter { _, version in
                guard !seen.contains(version) else { return false }
                seen.append(version)
                return true
            }
            .map(\.0)
    }
}

/// What the What's new window shows below the news of this build.
public struct WhatsNewSections: Equatable {
    /// The features only LidAwake Pro has.
    public let showsProFeatures: Bool
    /// The discount on LidAwake Pro; nil when none runs.
    public let discount: UpdateOffer?

    /// `showsPro` is whether this build offers LidAwake Pro; `offer` is what
    /// `UpdateChecker.offer` gives, so it is nil when the check is off or the offer is over.
    public init(showsPro: Bool, offer: UpdateOffer?) {
        showsProFeatures = showsPro
        discount = showsPro ? offer : nil
    }
}

/// The links at the bottom of How to use LidAwake. Fixed here, never taken from the settings or
/// the network.
public enum ProjectLink: Equatable, CaseIterable {
    case website
    case sourceCode

    public static let sourceCodePage = URL(string: "https://github.com/Vladimir-Podgornyi/LidAwake")!

    /// `language` is the language the app's interface is shown in.
    public func url(language: String?) -> URL {
        switch self {
        case .website: return ProOfferLink.page(language: language)
        case .sourceCode: return Self.sourceCodePage
        }
    }
}

/// The colors of the What's new window that do not follow the accent.
public enum PicturePalette {
    /// Behind every picture.
    public static let background = ThemedRGB(light: 0xE9ECF0, dark: 0x34373C)
    /// The screens of the laptop and the TV.
    public static let screen = ThemedRGB(light: 0x2E3239, dark: 0x141518)
    public static let tileBorder = ThemedRGB(light: 0xD3D7DD, dark: 0x3C4046)
    /// The bars of downloads, exports and heat, whatever the accent.
    public static let waitBar = ThemedRGB(light: 0xE8A33A, dark: 0xE8A33A)
    /// Secondary text; the system's secondary label falls below 4.5:1 on white.
    public static let secondaryText = ThemedRGB(light: 0x5F636B, dark: 0xA3A6AB)

    /// Text on an accent-colored badge: dark or white, whichever stands out more.
    public static func text(on accent: UInt32) -> UInt32 {
        let dark: UInt32 = 0x17181B
        let white: UInt32 = 0xFFFFFF
        return Contrast.ratio(white, accent) >= Contrast.ratio(dark, accent) ? white : dark
    }
}
