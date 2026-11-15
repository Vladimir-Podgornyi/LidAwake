import Foundation
import LidAwakeCore

/// `--check-update`: checks right away, ignoring the setting and the daily limit,
/// and saves nothing.
enum UpdateCommand {
    static let flag = "--check-update"

    static func run() async -> Int32 {
        let current = AppVersion.installedText
        let answer = await UpdateBuild.source(appVersion: current).answer()
        var offer: UpdateOffer?
        if case .offer(let read) = answer.offer { offer = read }
        let report = UpdateCheckReport.line(
            result: answer.result,
            current: current,
            intel: UpdateBuild.isIntel,
            origin: answer.origin,
            offer: offer
        )
        print(report.text)
        return report.exitCode
    }
}
