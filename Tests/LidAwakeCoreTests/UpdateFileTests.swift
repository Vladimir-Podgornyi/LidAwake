import XCTest
@testable import LidAwakeCore

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func date(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: text)!
}

/// 2026-11-20 12:00 in Berlin.
private let midNovember = date("2026-11-20T11:00:00Z")

private let offerJSON = """
{"percent":15,"price":"9.99","sale":"8.49","until":"2026-12-03","url":"https://buy.polar.sh/polar_cl_abc"}
"""

private func file(_ offer: String? = offerJSON, version: String = "1.1.1") -> Data {
    let body = offer.map { "{\"version\":\"\(version)\",\"offer\":\($0)}" } ?? "{\"version\":\"\(version)\"}"
    return Data(body.utf8)
}

private func offer(
    percent: Int = 15,
    price: String = "9.99",
    sale: String = "8.49",
    until: String = "2026-12-03",
    url: String = "https://buy.polar.sh/polar_cl_abc"
) -> String {
    "{\"percent\":\(percent),\"price\":\"\(price)\",\"sale\":\"\(sale)\",\"until\":\"\(until)\",\"url\":\"\(url)\"}"
}

final class UpdateFileTests: XCTestCase {
    private func read(_ body: Data, status: Int = 200, now: Date = midNovember) throws -> UpdateFileReading {
        try UpdateFile.read(status: status, body: body, now: now, calendar: berlin)
    }

    private func readOffer(_ offerText: String) throws -> UpdateOffer? {
        try read(file(offerText)).offer
    }

    func testFileWithOffer() throws {
        let reading = try read(file())
        XCTAssertEqual(reading.lookup, .tag("1.1.1"))
        let offer = try XCTUnwrap(reading.offer)
        XCTAssertEqual(offer.percent, 15)
        XCTAssertEqual(offer.priceAmount, Decimal(string: "9.99"))
        XCTAssertEqual(offer.saleAmount, Decimal(string: "8.49"))
        XCTAssertEqual(offer.until, "2026-12-03")
        XCTAssertEqual(offer.url.absoluteString, "https://buy.polar.sh/polar_cl_abc")
    }

    func testFileWithoutOffer() throws {
        let reading = try read(Data("{\"version\":\"1.1.1\"}".utf8))
        XCTAssertEqual(reading, UpdateFileReading(lookup: .tag("1.1.1"), offer: nil))
    }

    func testRepositoryFileIsReadable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let body = try Data(contentsOf: root.appendingPathComponent("update.json"))
        XCTAssertEqual(try read(body).lookup, .tag("1.1.1"))
    }

    func testPercentOutsideTheRangeDropsOnlyTheOffer() throws {
        for percent in [0, 4, 91, 100, -15] {
            let reading = try read(file(offer(percent: percent)))
            XCTAssertNil(reading.offer, "\(percent)")
            XCTAssertEqual(reading.lookup, .tag("1.1.1"))
        }
        XCTAssertNotNil(try readOffer(offer(percent: 5)))
        XCTAssertNotNil(try readOffer(offer(percent: 90)))
        XCTAssertNil(try readOffer(offer().replacingOccurrences(of: "15", with: "15.5")))
        XCTAssertNil(try readOffer(offer().replacingOccurrences(of: "15", with: "\"15\"")))
    }

    func testSaleMustBeBelowPrice() throws {
        XCTAssertNil(try readOffer(offer(sale: "9.99")))
        XCTAssertNil(try readOffer(offer(sale: "10.00")))
        XCTAssertNil(try readOffer(offer(sale: "0")))
        XCTAssertNotNil(try readOffer(offer(price: "10", sale: "8.5")))
    }

    func testPricesAreDecimalsWithADot() throws {
        for price in ["9,99", "9.999", ".99", "9.", "-9.99", "9.99 €", "1e3", "", "123456"] {
            XCTAssertNil(try readOffer(offer(price: price, sale: "0.50")), price)
        }
    }

    func testLinkHostIsChecked() throws {
        for url in [
            "https://evil.example/buy",
            "https://buy.polar.sh.evil.example/x",
            "https://polar.sh/erstgebaut",
            "http://buy.polar.sh/x",
            "https://buy.polar.sh:8443/x",
            "https://user@buy.polar.sh/x",
            "https://buy.polar.sh/x#part",
            "https://www.erstgebaut.de/lidawake",
            "javascript:alert(1)",
            "not a link",
        ] {
            XCTAssertNil(try readOffer(offer(url: url)), url)
        }
        XCTAssertNotNil(try readOffer(offer(url: "https://erstgebaut.de/lidawake/")))
        XCTAssertNotNil(try readOffer(offer(url: "https://buy.polar.sh/polar_cl_abc?discount=X")))
    }

    func testOfferLastsThroughItsLastDayInLocalTime() throws {
        // 23:59 on 3 December in Berlin is 22:59 UTC.
        XCTAssertNotNil(try read(file(), now: date("2026-12-03T22:59:00Z")).offer)
        XCTAssertNil(try read(file(), now: date("2026-12-03T23:00:00Z")).offer)
        XCTAssertNil(try read(file(), now: date("2027-01-01T00:00:00Z")).offer)
    }

    func testDateMustBeARealDay() throws {
        for until in ["2026-02-30", "2026-13-01", "26-12-03", "2026-12-3", "03.12.2026", "2026-12-03T00:00", ""] {
            XCTAssertNil(try readOffer(offer(until: until)), until)
        }
    }

    func testIncompleteOfferIsIgnored() throws {
        XCTAssertNil(try readOffer("{\"percent\":15}"))
        XCTAssertNil(try readOffer("\"15%\""))
        XCTAssertNil(try readOffer("null"))
    }

    func testUnreadableFilesGiveNoAnswer() {
        let bodies = [
            "",
            "garbage",
            "<html></html>",
            "[]",
            "{\"version\":1}",
            "{\"tag_name\":\"v1.1.1\"}",
        ]
        for body in bodies {
            XCTAssertThrowsError(try read(Data(body.utf8)), body) { error in
                XCTAssertEqual(error as? ReleaseLookupError, .badResponse, body)
            }
        }
        for version in ["v1.1.1", "1.1", "1.1.1.1", "1.1.x", ""] {
            XCTAssertThrowsError(try read(file(nil, version: version)), version) { error in
                XCTAssertEqual(error as? ReleaseLookupError, .badTag, version)
            }
        }
    }

    func testStatusOtherThan200GivesNoAnswer() {
        XCTAssertThrowsError(try read(file(), status: 404)) { error in
            XCTAssertEqual(error as? ReleaseLookupError, .status(404))
        }
    }

    func testReplyOverTheSizeLimitGivesNoAnswer() {
        let padding = String(repeating: " ", count: 4097 - file().count)
        let large = Data((String(decoding: file(), as: UTF8.self) + padding).utf8)
        XCTAssertEqual(large.count, 4097)
        XCTAssertThrowsError(try read(large))
        XCTAssertNoThrow(try read(large.prefix(4096)))
    }

    func testFileAddressIsFixed() {
        XCTAssertEqual(
            UpdateFileLinks.file.absoluteString,
            "https://raw.githubusercontent.com/Vladimir-Podgornyi/LidAwake/main/update.json"
        )
        XCTAssertTrue(UpdateFileLinks.isAllowed(UpdateFileLinks.file))
        for other in [
            "http://raw.githubusercontent.com/x",
            "https://raw.githubusercontent.com:444/x",
            "https://objects.githubusercontent.com/x",
            "https://github.com/Vladimir-Podgornyi/LidAwake/raw/main/update.json",
        ] {
            XCTAssertFalse(UpdateFileLinks.isAllowed(URL(string: other)!), other)
        }
    }

    func testSavedOfferIsCheckedAgainWhenRead() throws {
        let saved = try XCTUnwrap(try readOffer(offerJSON))
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(UpdateOffer.self, from: data), saved)
        let tampered = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "buy.polar.sh", with: "evil.example").utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(UpdateOffer.self, from: tampered))
    }
}

private final class FakeFileRequest: FileRequest, @unchecked Sendable {
    private let reply: Result<(status: Int, body: Data), ReleaseLookupError>
    private(set) var asked: [URL] = []

    init(_ reply: Result<(status: Int, body: Data), ReleaseLookupError>) {
        self.reply = reply
    }

    func get(_ url: URL) async throws -> (status: Int, body: Data) {
        asked.append(url)
        return try reply.get()
    }
}

private final class FakeUpdateSource: UpdateSource, @unchecked Sendable {
    var answerToGive: UpdateAnswer
    private(set) var calls = 0

    init(_ answer: UpdateAnswer) {
        answerToGive = answer
    }

    func answer() async -> UpdateAnswer {
        calls += 1
        return answerToGive
    }
}

final class FileFirstUpdateSourceTests: XCTestCase {
    private func answer(
        _ reply: Result<(status: Int, body: Data), ReleaseLookupError>,
        now: Date = midNovember
    ) async -> (answer: UpdateAnswer, request: FakeFileRequest, fallback: FakeUpdateSource) {
        let request = FakeFileRequest(reply)
        let fallback = FakeUpdateSource(UpdateAnswer(result: .success(.tag("v1.0.9")), origin: .web))
        let source = FileFirstUpdateSource(request: request, fallback: fallback, now: { now })
        return (await source.answer(), request, fallback)
    }

    func testFileAnswersAlone() async throws {
        let check = await answer(.success((200, file())))
        XCTAssertEqual(check.request.asked, [UpdateFileLinks.file])
        XCTAssertEqual(check.fallback.calls, 0)
        XCTAssertEqual(check.answer.origin, .file)
        XCTAssertEqual(try check.answer.result.get(), .tag("1.1.1"))
        guard case .offer(let offer) = check.answer.offer else { return XCTFail("no offer") }
        XCTAssertEqual(offer.percent, 15)
    }

    func testFileWithoutOfferSaysSo() async {
        let check = await answer(.success((200, file(nil))))
        XCTAssertEqual(check.answer.origin, .file)
        XCTAssertEqual(check.answer.offer, OfferReading.none)
    }

    func testExpiredOfferCountsAsNone() async {
        let check = await answer(.success((200, file())), now: date("2026-12-10T12:00:00Z"))
        XCTAssertEqual(check.answer.offer, OfferReading.none)
    }

    func testFailuresFallBackWithoutAnOffer() async throws {
        let replies: [Result<(status: Int, body: Data), ReleaseLookupError>] = [
            .failure(.timeout),
            .failure(.offline),
            .failure(.network),
            .failure(.badResponse),
            .success((404, Data())),
            .success((200, Data("garbage".utf8))),
            .success((200, file(nil, version: "v1.1.1"))),
        ]
        for reply in replies {
            let check = await answer(reply)
            XCTAssertEqual(check.fallback.calls, 1, "\(reply)")
            XCTAssertEqual(check.answer.origin, .web, "\(reply)")
            XCTAssertEqual(try check.answer.result.get(), .tag("v1.0.9"), "\(reply)")
            XCTAssertEqual(check.answer.offer, .notRead, "\(reply)")
        }
    }

    func testWebSourceReadsNoOffer() async {
        final class Redirect: RedirectRequest, @unchecked Sendable {
            func head(_ url: URL) async throws -> (status: Int, location: String?) {
                (302, "https://github.com/Vladimir-Podgornyi/LidAwake/releases/tag/v1.1.1")
            }
        }
        let source = WebFirstReleaseSource(request: Redirect(), fallback: GitHubReleaseSource(), intel: true)
        let answer = await source.answer()
        XCTAssertEqual(answer.offer, .notRead)
        XCTAssertEqual(answer.origin, .web)
    }
}

@MainActor
final class UpdateCheckerOfferTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock = midNovember

    override func setUp() {
        super.setUp()
        suiteName = "UpdateFileTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let sample = UpdateOffer(
        percent: 15, price: "9.99", sale: "8.49", until: "2026-12-03", url: "https://buy.polar.sh/polar_cl_abc"
    )!

    private func checker(_ source: FakeUpdateSource) -> UpdateChecker {
        UpdateChecker(defaults: defaults, source: source, currentVersion: "1.1.1", now: { [unowned self] in clock })
    }

    private func fromFile(_ offer: OfferReading, tag: String = "1.1.1") -> FakeUpdateSource {
        FakeUpdateSource(UpdateAnswer(result: .success(.tag(tag)), origin: .file, offer: offer))
    }

    func testOfferIsSavedAndShownOffline() async {
        let checker = checker(fromFile(.offer(sample)))
        XCTAssertNil(checker.offer)
        await checker.checkIfDue()
        XCTAssertEqual(checker.offer, sample)
        XCTAssertNil(checker.notice)
        // A new launch without network still shows it.
        let offline = self.checker(FakeUpdateSource(UpdateAnswer(result: .failure(ReleaseLookupError.offline), origin: .web)))
        XCTAssertEqual(offline.offer, sample)
    }

    func testFileWithoutOfferRemovesTheSavedOne() async {
        let first = checker(fromFile(.offer(sample)))
        await first.checkIfDue()
        clock = clock.addingTimeInterval(UpdateChecker.interval)
        let source = fromFile(.none)
        let second = checker(source)
        XCTAssertEqual(second.offer, sample)
        await second.checkIfDue()
        XCTAssertNil(second.offer)
        XCTAssertNil(defaults.data(forKey: UpdateChecker.offerKey))
        XCTAssertNil(checker(source).offer)
    }

    func testAnswerFromTheFallbackKeepsTheSavedOffer() async {
        await checker(fromFile(.offer(sample))).checkIfDue()
        clock = clock.addingTimeInterval(UpdateChecker.interval)
        let checker = checker(FakeUpdateSource(UpdateAnswer(result: .success(.tag("v1.1.2")), origin: .api)))
        await checker.checkIfDue()
        XCTAssertEqual(checker.offer, sample)
        XCTAssertEqual(checker.notice?.latest, "1.1.2")
    }

    func testFailedCheckKeepsTheSavedOffer() async {
        await checker(fromFile(.offer(sample))).checkIfDue()
        clock = clock.addingTimeInterval(UpdateChecker.interval)
        let checker = checker(FakeUpdateSource(UpdateAnswer(result: .failure(ReleaseLookupError.timeout), origin: .web)))
        await checker.checkIfDue()
        XCTAssertEqual(checker.offer, sample)
    }

    func testOfferEndsWithItsLastDay() async {
        let checker = checker(fromFile(.offer(sample)))
        await checker.checkIfDue()
        clock = date("2026-12-03T22:00:00Z")
        XCTAssertNotNil(checker.offer)
        clock = date("2026-12-05T00:00:00Z")
        XCTAssertNil(checker.offer)
    }

    func testTurningOffTheCheckHidesTheOffer() async {
        let checker = checker(fromFile(.offer(sample)))
        await checker.checkIfDue()
        checker.isEnabled = false
        XCTAssertNil(checker.offer)
        checker.isEnabled = true
        XCTAssertEqual(checker.offer, sample)
    }

    func testCheckTurnedOffReadsNoOffer() async {
        defaults.set(false, forKey: UpdateChecker.enabledKey)
        let source = fromFile(.offer(sample))
        let checker = checker(source)
        await checker.checkIfDue()
        XCTAssertEqual(source.calls, 0)
        XCTAssertNil(checker.offer)
        XCTAssertNil(defaults.data(forKey: UpdateChecker.offerKey))
    }

    func testBrokenSavedOfferIsIgnored() {
        defaults.set(Data("{\"percent\":95}".utf8), forKey: UpdateChecker.offerKey)
        XCTAssertNil(checker(fromFile(.none)).offer)
    }
}

final class ProOfferCardTests: XCTestCase {
    private let sample = UpdateOffer(
        percent: 15, price: "9.99", sale: "8.49", until: "2026-12-03", url: "https://erstgebaut.de/lidawake/"
    )!

    func testDiscountReplacesThePlainCard() {
        XCTAssertEqual(ProOfferCard.card(isShown: true, offer: sample), .discount(sample))
        XCTAssertEqual(ProOfferCard.card(isShown: true, offer: nil), .plain)
    }

    func testNoCardWhereProIsNotShown() {
        XCTAssertNil(ProOfferCard.card(isShown: false, offer: sample))
        XCTAssertNil(ProOfferCard.card(isShown: false, offer: nil))
    }

    @MainActor
    func testCheckTurnedOffShowsThePlainCard() async {
        let suite = "ProOfferCardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = FakeUpdateSource(UpdateAnswer(result: .success(.tag("1.1.1")), origin: .file, offer: .offer(sample)))
        let checker = UpdateChecker(defaults: defaults, source: source, currentVersion: "1.1.1", now: { midNovember })
        await checker.checkIfDue()
        XCTAssertEqual(ProOfferCard.card(isShown: true, offer: checker.offer), .discount(sample))
        checker.isEnabled = false
        XCTAssertEqual(ProOfferCard.card(isShown: true, offer: checker.offer), .plain)
    }

    func testPricesAndDayFollowTheInterfaceLanguage() {
        let nbsp = "\u{00A0}"
        XCTAssertEqual(OfferFormat.price(sample.saleAmount, language: "en"), "€8.49")
        XCTAssertEqual(OfferFormat.price(sample.saleAmount, language: "de"), "8,49\(nbsp)€")
        XCTAssertEqual(OfferFormat.price(sample.priceAmount, language: "ru"), "9,99\(nbsp)€")
        XCTAssertEqual(OfferFormat.price(sample.priceAmount, language: "zh-Hans"), "€9.99")
        let day = sample.lastDay(calendar: berlin)!
        XCTAssertEqual(OfferFormat.day(day, language: "en", timeZone: berlin.timeZone), "December 3")
        XCTAssertEqual(OfferFormat.day(day, language: "de", timeZone: berlin.timeZone), "3. Dezember")
        XCTAssertEqual(OfferFormat.day(day, language: "ru", timeZone: berlin.timeZone), "3 декабря")
        XCTAssertEqual(OfferFormat.day(day, language: "zh-Hans", timeZone: berlin.timeZone), "12月3日")
    }
}

final class UpdateCheckReportOfferTests: XCTestCase {
    func testOfferAndFileSource() {
        let offer = UpdateOffer(
            percent: 15, price: "9.99", sale: "8.49", until: "2026-12-03", url: "https://buy.polar.sh/x"
        )!
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.tag("1.1.1")), current: "1.1.1", origin: .file, offer: offer).text,
            "update=none latest=1.1.1 current=1.1.1 offer=15% until=2026-12-03 source=file"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.tag("1.1.1")), current: "1.1.1", origin: .file).text,
            "update=none latest=1.1.1 current=1.1.1 source=file"
        )
    }
}
