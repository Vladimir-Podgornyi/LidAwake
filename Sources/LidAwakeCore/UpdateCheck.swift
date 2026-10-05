import Combine
import Foundation

/// A release number: one to four dot-separated numbers, compared numerically.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let components: [Int]
    /// The number as written, without a leading "v".
    public let description: String

    /// Accepts "1.2", "v1.2.3" and the like; anything else is nil.
    public init?(_ text: String) {
        let number = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else {
                return nil
            }
            components.append(value)
        }
        self.components = components
        description = number
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// Missing components count as zero, so 1.0 equals 1.0.0.
    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }

    /// CFBundleShortVersionString of the running app.
    public static var installedText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

public enum UpdateLinks {
    public static let latestRelease = URL(string: "https://api.github.com/repos/Vladimir-Podgornyi/LidAwake/releases/latest")!
    /// Opened by the Download button. Never taken from a server reply.
    public static let downloadPage = URL(string: "https://github.com/Vladimir-Podgornyi/LidAwake/releases/latest")!
}

public enum ReleaseLookup: Equatable {
    /// The tag_name of the latest release, unchecked.
    case tag(String)
    /// The repository has no published release yet (404).
    case noReleases
}

public enum ReleaseLookupError: Error, Equatable {
    case timeout
    case offline
    case network
    case status(Int)
    case badResponse
    case badTag

    /// A short token for the --check-update line.
    public var reason: String {
        switch self {
        case .timeout: return "timeout"
        case .offline: return "offline"
        case .network: return "network"
        case .status(let code): return "http-\(code)"
        case .badResponse: return "bad-response"
        case .badTag: return "bad-tag"
        }
    }
}

public protocol ReleaseSource: Sendable {
    func latestRelease() async throws -> ReleaseLookup
}

/// Asks GitHub for the latest release. Sends no cookies, credentials or data about the user,
/// keeps nothing on disk and reads only tag_name from the reply.
public struct GitHubReleaseSource: ReleaseSource {
    private let session: URLSession
    private let userAgent: String

    public init(appVersion: String = AppVersion.installedText) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
        userAgent = "LidAwake/\(appVersion)"
    }

    public func latestRelease() async throws -> ReleaseLookup {
        var request = URLRequest(url: UpdateLinks.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw ReleaseLookupError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw ReleaseLookupError.offline
            default: throw ReleaseLookupError.network
            }
        } catch {
            throw ReleaseLookupError.network
        }
        guard let http = response as? HTTPURLResponse else { throw ReleaseLookupError.badResponse }
        return try Self.lookup(status: http.statusCode, body: data)
    }

    static func lookup(status: Int, body: Data) throws -> ReleaseLookup {
        switch status {
        case 200:
            struct Release: Decodable {
                let tag_name: String
            }
            guard let release = try? JSONDecoder().decode(Release.self, from: body) else {
                throw ReleaseLookupError.badResponse
            }
            return .tag(release.tag_name)
        case 404:
            return .noReleases
        default:
            throw ReleaseLookupError.status(status)
        }
    }
}

/// The outcome of one --check-update run.
public enum UpdateCheckReport {
    public static func line(result: Result<ReleaseLookup, Error>, current: String) -> (text: String, exitCode: Int32) {
        func error(_ reason: String) -> (String, Int32) {
            ("update=error reason=\(reason) current=\(current)", 1)
        }
        guard let installed = AppVersion(current) else { return error("bad-current-version") }
        switch result {
        case .success(.noReleases):
            return ("update=none reason=no-releases current=\(current)", 0)
        case .success(.tag(let tag)):
            guard let latest = AppVersion(tag) else { return error(ReleaseLookupError.badTag.reason) }
            let state = latest > installed ? "available" : "none"
            return ("update=\(state) latest=\(latest) current=\(current)", 0)
        case .failure(let failure):
            return error((failure as? ReleaseLookupError)?.reason ?? "network")
        }
    }
}

/// The Update available banner.
public struct UpdateNotice: Equatable {
    public let latest: String
    public let current: String
}

/// Checks GitHub for a newer release at most once a day. Kept apart from `SafetyPreferences`:
/// nothing here reaches the helper.
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let enabledKey = "updateCheckEnabled"
    public static let lastCheckKey = "updateLastCheck"
    public static let latestVersionKey = "updateLatestVersion"

    public static let interval: TimeInterval = 24 * 60 * 60
    public static let launchDelay: TimeInterval = 10
    /// How often the running app looks whether a check is due. Waking up often instead of
    /// sleeping a whole day keeps the schedule right across system sleep and clock changes.
    public static let pollInterval: TimeInterval = 60 * 60

    @Published public var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published public private(set) var latestVersion: AppVersion?

    private let defaults: UserDefaults
    private let source: ReleaseSource
    private let currentText: String
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private var loop: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        source: ReleaseSource = GitHubReleaseSource(),
        currentVersion: String = AppVersion.installedText,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.defaults = defaults
        self.source = source
        currentText = currentVersion
        self.now = now
        self.sleep = sleep
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        latestVersion = defaults.string(forKey: Self.latestVersionKey).flatMap(AppVersion.init)
    }

    /// The banner to show, or nil when the check is off or the installed version is not older.
    public var notice: UpdateNotice? {
        guard isEnabled, let latest = latestVersion, let current = AppVersion(currentText), current < latest else {
            return nil
        }
        return UpdateNotice(latest: latest.description, current: currentText)
    }

    /// Checks 10 seconds after launch, then whenever a day has passed since the last check.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self, sleep] in
            do {
                try await sleep(Self.launchDelay)
                while !Task.isCancelled {
                    await self?.checkIfDue()
                    try await sleep(Self.pollInterval)
                }
            } catch {}
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public var isDue: Bool {
        guard let last = defaults.object(forKey: Self.lastCheckKey) as? Date else { return true }
        let elapsed = now().timeIntervalSince(last)
        // A last check in the future means the clock was set back; waiting for it could take years.
        return elapsed < 0 || elapsed >= Self.interval
    }

    /// Asks for the latest release when the check is on and due. Failures change nothing in
    /// the window; the next attempt comes a day later.
    public func checkIfDue() async {
        guard isEnabled, isDue else { return }
        defaults.set(now(), forKey: Self.lastCheckKey)
        guard case .tag(let tag)? = try? await source.latestRelease(), let latest = AppVersion(tag) else {
            return
        }
        defaults.set(latest.description, forKey: Self.latestVersionKey)
        latestVersion = latest
    }
}
