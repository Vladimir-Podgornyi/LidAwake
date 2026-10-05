import Combine
import XCTest
@testable import LidAwakeCore

final class AppVersionTests: XCTestCase {
    func testAcceptedTags() {
        let accepted: [(String, [Int], String)] = [
            ("1", [1], "1"),
            ("v1.2", [1, 2], "1.2"),
            ("1.2.3", [1, 2, 3], "1.2.3"),
            ("v1.2.3.4", [1, 2, 3, 4], "1.2.3.4"),
            ("0.10", [0, 10], "0.10"),
        ]
        for (tag, components, text) in accepted {
            let version = AppVersion(tag)
            XCTAssertEqual(version?.components, components, tag)
            XCTAssertEqual(version?.description, text, tag)
        }
    }

    func testRejectedTags() {
        let rejected = [
            "", "v", "V1.2", "vv1.2", "1.2.3.4.5", "1..2", "1.2.", ".1", " 1.2", "1.2 ",
            "1.2-beta", "v1.2.3-rc.1", "1.2.3a", "1.-2", "+1", "release-1.0", "latest",
            "١.٢", "99999999999999999999",
        ]
        for tag in rejected {
            XCTAssertNil(AppVersion(tag), tag)
        }
    }

    func testComparesNumbersNotText() {
        XCTAssertGreaterThan(AppVersion("1.10.0")!, AppVersion("1.9.0")!)
        XCTAssertGreaterThan(AppVersion("v2")!, AppVersion("1.99.99.99")!)
        XCTAssertGreaterThan(AppVersion("1.0.1")!, AppVersion("1.0")!)
        XCTAssertLessThan(AppVersion("0.9")!, AppVersion("1")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(AppVersion("v1")!, AppVersion("1.0.0.0")!)
        XCTAssertFalse(AppVersion("1.0")! < AppVersion("1.0.0")!)
        XCTAssertFalse(AppVersion("1.0.0")! < AppVersion("1.0")!)
    }
}

final class GitHubReleaseSourceTests: XCTestCase {
    func testReadsOnlyTheTagName() throws {
        let body = Data(#"{"tag_name":"v1.2.0","html_url":"https://example.com/elsewhere","name":"x"}"#.utf8)
        XCTAssertEqual(try GitHubReleaseSource.lookup(status: 200, body: body), .tag("v1.2.0"))
    }

    func testNotFoundMeansNoReleases() throws {
        XCTAssertEqual(try GitHubReleaseSource.lookup(status: 404, body: Data()), .noReleases)
    }

    func testOtherStatusIsAnError() {
        for status in [301, 403, 500, 503] {
            XCTAssertThrowsError(try GitHubReleaseSource.lookup(status: status, body: Data())) {
                XCTAssertEqual($0 as? ReleaseLookupError, .status(status))
            }
        }
    }

    func testUnreadableReplyIsAnError() {
        for body in ["", "<html>", "{}", #"{"tag_name":1}"#, "[]"] {
            XCTAssertThrowsError(try GitHubReleaseSource.lookup(status: 200, body: Data(body.utf8))) {
                XCTAssertEqual($0 as? ReleaseLookupError, .badResponse, body)
            }
        }
    }

    func testAddressesAreFixed() {
        XCTAssertEqual(
            UpdateLinks.latestRelease.absoluteString,
            "https://api.github.com/repos/Vladimir-Podgornyi/LidAwake/releases/latest"
        )
        XCTAssertEqual(
            UpdateLinks.downloadPage.absoluteString,
            "https://github.com/Vladimir-Podgornyi/LidAwake/releases/latest"
        )
    }
}

final class UpdateCheckReportTests: XCTestCase {
    func testLines() {
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.tag("v1.1.0")), current: "1.0.0").text,
            "update=available latest=1.1.0 current=1.0.0"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.tag("v1.0")), current: "1.0.0").text,
            "update=none latest=1.0 current=1.0.0"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.noReleases), current: "1.0.0").text,
            "update=none reason=no-releases current=1.0.0"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .success(.tag("nightly")), current: "1.0.0").text,
            "update=error reason=bad-tag current=1.0.0"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .failure(ReleaseLookupError.timeout), current: "1.0.0").text,
            "update=error reason=timeout current=1.0.0"
        )
        XCTAssertEqual(
            UpdateCheckReport.line(result: .failure(ReleaseLookupError.status(500)), current: "1.0.0").text,
            "update=error reason=http-500 current=1.0.0"
        )
    }

    func testExitCodeIsOneOnlyForErrors() {
        XCTAssertEqual(UpdateCheckReport.line(result: .success(.tag("v2")), current: "1.0.0").exitCode, 0)
        XCTAssertEqual(UpdateCheckReport.line(result: .success(.tag("v1")), current: "1.0.0").exitCode, 0)
        XCTAssertEqual(UpdateCheckReport.line(result: .success(.noReleases), current: "1.0.0").exitCode, 0)
        XCTAssertEqual(UpdateCheckReport.line(result: .failure(ReleaseLookupError.offline), current: "1.0.0").exitCode, 1)
        XCTAssertEqual(UpdateCheckReport.line(result: .success(.tag("v2")), current: "").exitCode, 1)
    }
}

private final class FakeReleaseSource: ReleaseSource, @unchecked Sendable {
    var result: Result<ReleaseLookup, Error>
    private(set) var calls = 0

    init(_ result: Result<ReleaseLookup, Error>) {
        self.result = result
    }

    func latestRelease() async throws -> ReleaseLookup {
        calls += 1
        return try result.get()
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "UpdateCheckTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func checker(_ source: FakeReleaseSource, current: String = "1.0.0") -> UpdateChecker {
        UpdateChecker(defaults: defaults, source: source, currentVersion: current, now: { [unowned self] in clock })
    }

    func testNewerReleaseShowsTheBanner() async {
        let checker = checker(FakeReleaseSource(.success(.tag("v1.10.0"))), current: "1.9.0")
        XCTAssertNil(checker.notice)
        await checker.checkIfDue()
        XCTAssertEqual(checker.notice, UpdateNotice(latest: "1.10.0", current: "1.9.0"))
        XCTAssertEqual(defaults.string(forKey: "updateLatestVersion"), "1.10.0")
    }

    func testEqualOrOlderReleaseShowsNothing() async {
        for tag in ["v1.0", "1.0.0", "v0.9.9"] {
            defaults.removeObject(forKey: "updateLastCheck")
            let checker = checker(FakeReleaseSource(.success(.tag(tag))))
            await checker.checkIfDue()
            XCTAssertNil(checker.notice, tag)
        }
    }

    func testFailuresPassSilently() async {
        let failures: [Result<ReleaseLookup, Error>] = [
            .failure(ReleaseLookupError.offline),
            .failure(ReleaseLookupError.timeout),
            .failure(ReleaseLookupError.status(500)),
            .failure(ReleaseLookupError.badResponse),
            .success(.noReleases),
            .success(.tag("nightly")),
        ]
        for result in failures {
            defaults.removeObject(forKey: "updateLastCheck")
            let source = FakeReleaseSource(result)
            let checker = checker(source)
            await checker.checkIfDue()
            XCTAssertEqual(source.calls, 1)
            XCTAssertNil(checker.notice)
            XCTAssertNil(defaults.object(forKey: "updateLatestVersion"))
            XCTAssertEqual(defaults.object(forKey: "updateLastCheck") as? Date, clock, "the next try waits a day")
        }
    }

    func testFailureKeepsAFoundVersion() async {
        defaults.set("1.1.0", forKey: "updateLatestVersion")
        for result: Result<ReleaseLookup, Error> in [.failure(ReleaseLookupError.offline), .success(.noReleases)] {
            defaults.removeObject(forKey: "updateLastCheck")
            let checker = checker(FakeReleaseSource(result))
            await checker.checkIfDue()
            XCTAssertEqual(checker.notice, UpdateNotice(latest: "1.1.0", current: "1.0.0"))
        }
    }

    func testDisabledMakesNoRequestAndHidesTheBanner() async {
        defaults.set(false, forKey: "updateCheckEnabled")
        defaults.set("2.0.0", forKey: "updateLatestVersion")
        let source = FakeReleaseSource(.success(.tag("v3.0.0")))
        let checker = checker(source)
        XCTAssertFalse(checker.isEnabled)
        await checker.checkIfDue()
        XCTAssertEqual(source.calls, 0)
        XCTAssertNil(checker.notice)
        XCTAssertNil(defaults.object(forKey: "updateLastCheck"))
    }

    func testToggleIsStoredAndOnByDefault() {
        let checker = checker(FakeReleaseSource(.success(.noReleases)))
        XCTAssertTrue(checker.isEnabled)
        checker.isEnabled = false
        XCTAssertEqual(defaults.object(forKey: "updateCheckEnabled") as? Bool, false)
        XCTAssertFalse(UpdateChecker(defaults: defaults, source: FakeReleaseSource(.success(.noReleases))).isEnabled)
        checker.isEnabled = true
        XCTAssertEqual(defaults.object(forKey: "updateCheckEnabled") as? Bool, true)
    }

    func testTurningOffHidesAFoundUpdate() async {
        let checker = checker(FakeReleaseSource(.success(.tag("v2.0.0"))))
        await checker.checkIfDue()
        XCTAssertNotNil(checker.notice)
        checker.isEnabled = false
        XCTAssertNil(checker.notice)
    }

    func testToggleDoesNotTouchSafetySettings() {
        let safety = SafetyPreferences(defaults: defaults)
        let before = safety.helperSettings
        var fired = false
        let subscription = safety.changes.sink { fired = true }
        let checker = checker(FakeReleaseSource(.success(.noReleases)))
        checker.isEnabled = false
        checker.isEnabled = true
        XCTAssertFalse(fired)
        XCTAssertEqual(SafetyPreferences(defaults: defaults).helperSettings, before)
        subscription.cancel()
    }

    func testAtMostOnceADay() async {
        let source = FakeReleaseSource(.success(.noReleases))
        let checker = checker(source)
        await checker.checkIfDue()
        XCTAssertEqual(source.calls, 1)
        clock += 23 * 3600 + 3599
        await checker.checkIfDue()
        XCTAssertEqual(source.calls, 1)
        clock += 1
        await checker.checkIfDue()
        XCTAssertEqual(source.calls, 2)
    }

    func testAtMostOnceADayAcrossRestarts() async {
        let first = FakeReleaseSource(.failure(ReleaseLookupError.offline))
        await checker(first).checkIfDue()
        XCTAssertEqual(first.calls, 1)

        clock += 3600
        let second = FakeReleaseSource(.success(.tag("v2.0.0")))
        await checker(second).checkIfDue()
        XCTAssertEqual(second.calls, 0)

        clock += 23 * 3600
        let third = FakeReleaseSource(.success(.tag("v2.0.0")))
        let checker = checker(third)
        await checker.checkIfDue()
        XCTAssertEqual(third.calls, 1)
        XCTAssertNotNil(checker.notice)
    }

    func testClockSetBackMakesTheCheckDue() async {
        defaults.set(clock + 7 * 24 * 3600, forKey: "updateLastCheck")
        let source = FakeReleaseSource(.success(.noReleases))
        await checker(source).checkIfDue()
        XCTAssertEqual(source.calls, 1)
    }

    func testStoredVersionShowsTheBannerAtOnce() {
        defaults.set("1.2.0", forKey: "updateLatestVersion")
        defaults.set(clock, forKey: "updateLastCheck")
        let source = FakeReleaseSource(.success(.noReleases))
        let checker = checker(source)
        XCTAssertEqual(checker.notice, UpdateNotice(latest: "1.2.0", current: "1.0.0"))
        XCTAssertEqual(source.calls, 0)
    }

    func testStoredVersionNoLongerNewerShowsNothing() {
        defaults.set("1.2.0", forKey: "updateLatestVersion")
        XCTAssertNil(checker(FakeReleaseSource(.success(.noReleases)), current: "1.2").notice)
        XCTAssertNil(checker(FakeReleaseSource(.success(.noReleases)), current: "1.3.0").notice)
    }

    func testFirstCheckTenSecondsAfterLaunchThenHourlyLooks() async {
        let source = FakeReleaseSource(.success(.tag("v2.0.0")))
        var sleeps: [TimeInterval] = []
        let finished = expectation(description: "second sleep")
        let checker = UpdateChecker(
            defaults: defaults,
            source: source,
            currentVersion: "1.0.0",
            now: { [unowned self] in clock },
            sleep: { delay in
                let count = await MainActor.run {
                    sleeps.append(delay)
                    return sleeps.count
                }
                if count == 2 {
                    finished.fulfill()
                    throw CancellationError()
                }
            }
        )
        checker.start()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(sleeps, [10, 3600])
        XCTAssertEqual(source.calls, 1)
        XCTAssertNotNil(checker.notice)
        checker.stop()
    }
}

final class UpdateMessageTests: XCTestCase {
    func testUpdateBannerComesLast() {
        let messages = WindowMessage.list(
            helper: .approval,
            mode: .turnedOff("The timer ran out."),
            update: UpdateNotice(latest: "1.1.0", current: "1.0.0")
        )
        XCTAssertEqual(messages.map(\.source), [.helper, .mode, .update])
        let update = messages[2]
        XCTAssertEqual(update.kind, .info)
        XCTAssertEqual(update.title, "Update available")
        XCTAssertEqual(update.text, "LidAwake 1.1.0 is available. You have 1.0.0.")
        XCTAssertEqual(update.actionTitle, "Download")
        XCTAssertNil(update.action)
    }

    func testUpdateBannerAlone() {
        let messages = WindowMessage.list(helper: nil, mode: nil, update: UpdateNotice(latest: "9.9.9", current: "1.0.0"))
        XCTAssertEqual(messages.map(\.source), [.update])
    }
}
