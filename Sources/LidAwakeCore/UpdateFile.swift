import Foundation

/// The update file in this repository, read by the Apple silicon build:
///
///     {"version": "x.y.z",
///      "offer": {"percent": 15, "price": "9.99", "sale": "8.49",
///                "until": "2026-12-03", "url": "https://buy.polar.sh/..."}}
///
/// `offer` is optional. Only these numbers, the date and the link are read; every word the
/// window shows comes from the app. Other fields are ignored.
public enum UpdateFileLinks {
    public static let file = URL(string: "https://raw.githubusercontent.com/Vladimir-Podgornyi/LidAwake/main/update.json")!
    static let host = "raw.githubusercontent.com"
    /// A larger reply is not read to the end and counts as no answer.
    static let sizeLimit = 4096

    static func isAllowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && parts.host == host && parts.port == nil
            && parts.user == nil && parts.password == nil
    }
}

/// A discount on LidAwake Pro, valid through the end of `until` in local time.
public struct UpdateOffer: Equatable, Sendable, Codable {
    public static let percentRange = 5...90
    /// Where the link may lead.
    public static let hosts: Set<String> = ["buy.polar.sh", "erstgebaut.de"]

    public let percent: Int
    /// Prices in EUR as written in the file, "9.99".
    public let price: String
    public let sale: String
    /// YYYY-MM-DD.
    public let until: String
    public let url: URL

    /// nil unless every field passes; the date is not compared with today here.
    public init?(percent: Int, price: String, sale: String, until: String, url: String) {
        guard Self.percentRange.contains(percent),
              let priceValue = Self.amount(price), let saleValue = Self.amount(sale),
              saleValue > 0, saleValue < priceValue,
              Self.day(until) != nil,
              let link = Self.link(url) else { return nil }
        self.percent = percent
        self.price = price
        self.sale = sale
        self.until = until
        self.url = link
    }

    public var priceAmount: Decimal { Self.amount(price) ?? 0 }
    public var saleAmount: Decimal { Self.amount(sale) ?? 0 }

    /// The first moment after the offer, in the time zone of `calendar`.
    public func end(calendar: Calendar = .current) -> Date? {
        guard let day = Self.day(until), let start = calendar.date(from: day) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    /// The first moment of the last day, for showing the date.
    public func lastDay(calendar: Calendar = .current) -> Date? {
        Self.day(until).flatMap(calendar.date(from:))
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let end = end(calendar: calendar) else { return false }
        return date < end
    }

    /// Digits, optionally a dot and one or two digits.
    static func amount(_ text: String) -> Decimal? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              (1...5).contains(parts[0].count),
              parts.count == 1 || (1...2).contains(parts[1].count),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// YYYY-MM-DD that names a real day.
    static func day(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return components
    }

    static func link(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text), parts.scheme == "https",
              let host = parts.host, hosts.contains(host),
              parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              let url = parts.url else { return nil }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case percent, price, sale, until, url
    }

    /// Values read back from the settings pass the same checks as the file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let offer = UpdateOffer(
            percent: try container.decode(Int.self, forKey: .percent),
            price: try container.decode(String.self, forKey: .price),
            sale: try container.decode(String.self, forKey: .sale),
            until: try container.decode(String.self, forKey: .until),
            url: try container.decode(String.self, forKey: .url)
        ) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid offer"))
        }
        self = offer
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(percent, forKey: .percent)
        try container.encode(price, forKey: .price)
        try container.encode(sale, forKey: .sale)
        try container.encode(until, forKey: .until)
        try container.encode(url.absoluteString, forKey: .url)
    }
}

/// What one reading of the update file gave.
public struct UpdateFileReading: Equatable {
    public let lookup: ReleaseLookup
    /// nil when the file has no offer, an offer that fails a check, or one already over.
    public let offer: UpdateOffer?
}

public enum UpdateFile {
    /// Any status but 200, a reply over the size limit or a version that is not
    /// digits.digits.digits gives no answer. A bad offer leaves the version usable.
    public static func read(status: Int, body: Data, now: Date, calendar: Calendar = .current) throws -> UpdateFileReading {
        guard status == 200 else { throw ReleaseLookupError.status(status) }
        guard body.count <= UpdateFileLinks.sizeLimit else { throw ReleaseLookupError.badResponse }
        struct VersionPart: Decodable {
            let version: String
        }
        struct OfferPart: Decodable {
            struct Fields: Decodable {
                let percent: Int
                let price: String
                let sale: String
                let until: String
                let url: String
            }
            let offer: Fields
        }
        guard let file = try? JSONDecoder().decode(VersionPart.self, from: body) else {
            throw ReleaseLookupError.badResponse
        }
        guard isVersion(file.version) else { throw ReleaseLookupError.badTag }
        let offer = (try? JSONDecoder().decode(OfferPart.self, from: body)).flatMap { part in
            UpdateOffer(
                percent: part.offer.percent,
                price: part.offer.price,
                sale: part.offer.sale,
                until: part.offer.until,
                url: part.offer.url
            )
        }
        return UpdateFileReading(
            lookup: .tag(file.version),
            offer: offer.flatMap { $0.isActive(at: now, calendar: calendar) ? $0 : nil }
        )
    }

    static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts.allSatisfy { part in !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } }
            && AppVersion(text) != nil
    }
}

/// A GET that does not follow redirects. Throws only `ReleaseLookupError`.
protocol FileRequest: Sendable {
    func get(_ url: URL) async throws -> (status: Int, body: Data)
}

/// Sends no cookies, credentials or data about the user and keeps nothing on disk. Asks only
/// https://raw.githubusercontent.com and reads at most `UpdateFileLinks.sizeLimit` bytes of a
/// 200 reply.
struct UpdateFileHTTPRequest: FileRequest {
    private let session: URLSession
    private let userAgent: String

    init(appVersion: String) {
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

    func get(_ url: URL) async throws -> (status: Int, body: Data) {
        guard UpdateFileLinks.isAllowed(url) else { throw ReleaseLookupError.badResponse }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Replaces the system default, which would tell the user's languages.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefusal())
            guard let http = response as? HTTPURLResponse, http.url.map(UpdateFileLinks.isAllowed) == true else {
                bytes.task.cancel()
                throw ReleaseLookupError.badResponse
            }
            guard http.statusCode == 200 else {
                bytes.task.cancel()
                return (http.statusCode, Data())
            }
            guard http.expectedContentLength <= Int64(UpdateFileLinks.sizeLimit) else {
                bytes.task.cancel()
                throw ReleaseLookupError.badResponse
            }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > UpdateFileLinks.sizeLimit {
                    bytes.task.cancel()
                    throw ReleaseLookupError.badResponse
                }
            }
            return (200, body)
        } catch let error as ReleaseLookupError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw ReleaseLookupError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw ReleaseLookupError.offline
            default: throw ReleaseLookupError.network
            }
        } catch {
            throw ReleaseLookupError.network
        }
    }
}

/// Whether a check read an offer, and which.
public enum OfferReading: Equatable, Sendable {
    /// The answer did not come from the update file; a saved offer stays as it is.
    case notRead
    /// The file was read and has no valid offer; a saved offer is removed.
    case none
    case offer(UpdateOffer)
}

/// The outcome of one check, as `UpdateChecker` and --check-update use it.
public struct UpdateAnswer {
    public let result: Result<ReleaseLookup, Error>
    public let origin: ReleaseOrigin?
    public let offer: OfferReading

    public init(result: Result<ReleaseLookup, Error>, origin: ReleaseOrigin?, offer: OfferReading = .notRead) {
        self.result = result
        self.origin = origin
        self.offer = offer
    }
}

public protocol UpdateSource: Sendable {
    func answer() async -> UpdateAnswer
}

/// A source that only knows releases; it never reads an offer.
public struct ReleaseOnlyUpdateSource: UpdateSource {
    private let source: ReleaseSource

    public init(_ source: ReleaseSource) {
        self.source = source
    }

    public func answer() async -> UpdateAnswer {
        do {
            return UpdateAnswer(result: .success(try await source.latestRelease()), origin: nil)
        } catch {
            return UpdateAnswer(result: .failure(error), origin: nil)
        }
    }
}

extension WebFirstReleaseSource: UpdateSource {
    public func answer() async -> UpdateAnswer {
        let check = await check()
        return UpdateAnswer(result: check.result, origin: check.origin)
    }
}

/// Reads the update file first. When it is not received or cannot be read, asks `fallback`,
/// which reads no offer.
public struct FileFirstUpdateSource: UpdateSource {
    private let request: FileRequest
    private let fallback: UpdateSource
    private let now: @Sendable () -> Date

    public init(appVersion: String = AppVersion.installedText) {
        self.init(
            request: UpdateFileHTTPRequest(appVersion: appVersion),
            fallback: WebFirstReleaseSource(intel: false, appVersion: appVersion)
        )
    }

    init(request: FileRequest, fallback: UpdateSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.request = request
        self.fallback = fallback
        self.now = now
    }

    public func answer() async -> UpdateAnswer {
        if let reply = try? await request.get(UpdateFileLinks.file),
           let reading = try? UpdateFile.read(status: reply.status, body: reply.body, now: now()) {
            return UpdateAnswer(
                result: .success(reading.lookup),
                origin: .file,
                offer: reading.offer.map(OfferReading.offer) ?? .none
            )
        }
        return await fallback.answer()
    }
}
