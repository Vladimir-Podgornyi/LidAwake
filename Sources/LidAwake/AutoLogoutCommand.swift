import Foundation
import LidAwakeCore

/// `--auto-logout-status`: prints the macOS automatic logout delay and exits.
enum AutoLogoutCommand {
    static let flag = "--auto-logout-status"

    static func run() -> Int32 {
        print(AutoLogoutReport.line(delaySeconds: SystemAutoLogoutSource().delaySeconds()))
        return 0
    }
}
