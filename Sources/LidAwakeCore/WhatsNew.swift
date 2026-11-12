import Foundation

/// When the What's new window opens by itself: on the first launch of a build whose news differ
/// from the ones last shown, the very first launch of the app included. Once for each version.
public struct WhatsNewLaunch {
    public static let shownVersionKey = "whatsNewShownVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `version` is the version the news of this build describe.
    public func opensByItself(version: String) -> Bool {
        defaults.string(forKey: Self.shownVersionKey) != version
    }

    public func markShown(version: String) {
        defaults.set(version, forKey: Self.shownVersionKey)
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
