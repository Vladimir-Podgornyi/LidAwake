import Foundation
import LidAwakeCore

/// `--check-update`: asks GitHub once, right away, ignoring the setting and the daily limit,
/// and saves nothing.
enum UpdateCommand {
    static let flag = "--check-update"

    static func run() async -> Int32 {
        let current = AppVersion.installedText
        let result: Result<ReleaseLookup, Error>
        do {
            result = .success(try await GitHubReleaseSource(appVersion: current).latestRelease())
        } catch {
            result = .failure(error)
        }
        let report = UpdateCheckReport.line(result: result, current: current)
        print(report.text)
        return report.exitCode
    }
}
