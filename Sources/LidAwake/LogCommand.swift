import Foundation
import LidAwakeCore

/// `--print-log`: prints the activity log, oldest first, one event per line, and exits.
/// It only reads, so a missing log stays missing.
enum LogCommand {
    static let flag = "--print-log"

    static func run() -> Int32 {
        for entry in ActivityLog.read(from: ActivityLog.defaultFileURL) {
            print(ActivityToken.line(for: entry))
        }
        return 0
    }
}
