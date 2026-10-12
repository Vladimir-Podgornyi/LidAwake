import Foundation
import LidAwakeCore

/// `--check-update`: checks GitHub right away, ignoring the setting and the daily limit,
/// and saves nothing.
enum UpdateCommand {
    static let flag = "--check-update"

    static func run() async -> Int32 {
        let current = AppVersion.installedText
        let check = await UpdateBuild.source(appVersion: current).check()
        let report = UpdateCheckReport.line(result: check.result, current: current, intel: UpdateBuild.isIntel, origin: check.origin)
        print(report.text)
        return report.exitCode
    }
}
