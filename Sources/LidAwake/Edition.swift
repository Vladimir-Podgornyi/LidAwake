import Foundation
import LidAwakeCore

/// Everything that differs between LidAwake and LidAwake Pro. The rest of the code asks this
/// file and never decides by itself which of the two it is.
enum Edition {
    /// The version the What's new window describes. When it changes, the window opens by itself
    /// once, on the first launch of the new build.
    static let whatsNewVersion = "1.2.0"

    /// The news of this build, top to bottom.
    static let whatsNew: [WhatsNewFeature] = [.languages]

    /// The version of LidAwake Pro the Pro block names.
    static let proVersion = "1.3.0"

    /// The tiles of the "Only in LidAwake Pro" block, row by row.
    static let proFeatures: [WhatsNewFeature] = [.movieOnTV, .downloads, .exports, .inABag]

    /// The Pro block and the discount in What's new; Pro is released for Apple silicon only.
    static var showsProOffer: Bool { ProOffer.isShown }

    /// The links at the bottom of How to use LidAwake.
    static let helpLinks: [ProjectLink] = [.website, .sourceCode]
}
