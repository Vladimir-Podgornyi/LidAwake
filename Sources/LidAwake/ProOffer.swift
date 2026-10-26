import Foundation
import LidAwakeCore

/// Whether the settings show the LidAwake Pro row, and where it leads. Pro is released for
/// Apple silicon only.
enum ProOffer {
    #if arch(x86_64)
    static let isShown = false
    #else
    static let isShown = true
    #endif

    static var page: URL {
        ProOfferLink.page(language: Bundle.main.preferredLocalizations.first)
    }
}
