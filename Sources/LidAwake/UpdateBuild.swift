import Foundation
import LidAwakeCore

/// The Intel build looks only at releases that carry an Intel disk image; the Apple silicon build
/// reads the update file first, which can also carry an offer.
enum UpdateBuild {
    #if arch(x86_64)
    static let isIntel = true

    static func source(appVersion: String = AppVersion.installedText) -> UpdateSource {
        WebFirstReleaseSource(intel: true, appVersion: appVersion)
    }

    static func downloadPage(for notice: UpdateNotice?) -> URL {
        notice.map { IntelRelease.releasePage(version: $0.latest) } ?? UpdateLinks.releasesPage
    }
    #else
    static let isIntel = false

    static func source(appVersion: String = AppVersion.installedText) -> UpdateSource {
        FileFirstUpdateSource(appVersion: appVersion)
    }

    static func downloadPage(for notice: UpdateNotice?) -> URL {
        UpdateLinks.downloadPage
    }
    #endif
}
