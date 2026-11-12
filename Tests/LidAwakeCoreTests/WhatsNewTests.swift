import XCTest
@testable import LidAwakeCore

final class WhatsNewLaunchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewLaunchTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOpensOnTheVeryFirstLaunch() {
        XCTAssertTrue(WhatsNewLaunch(defaults: defaults).opensByItself(version: "1.2.0"))
    }

    func testOpensOnceForEachVersion() {
        let launch = WhatsNewLaunch(defaults: defaults)
        launch.markShown(version: "1.2.0")
        XCTAssertFalse(launch.opensByItself(version: "1.2.0"))
        XCTAssertFalse(WhatsNewLaunch(defaults: defaults).opensByItself(version: "1.2.0"), "after a restart too")
    }

    func testOpensForANewVersion() {
        let launch = WhatsNewLaunch(defaults: defaults)
        launch.markShown(version: "1.2.0")
        XCTAssertTrue(launch.opensByItself(version: "1.3.0"))
        launch.markShown(version: "1.3.0")
        XCTAssertFalse(launch.opensByItself(version: "1.3.0"))
    }

    func testRemembersTheVersionUnderItsKey() {
        WhatsNewLaunch(defaults: defaults).markShown(version: "1.2.0")
        XCTAssertEqual(defaults.string(forKey: WhatsNewLaunch.shownVersionKey), "1.2.0")
    }
}

@MainActor
final class WhatsNewSectionsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let offer = UpdateOffer(
        percent: 20, price: "9.99", sale: "7.99", until: "2026-12-03", url: "https://buy.polar.sh/polar_cl_abc"
    )!

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewSectionsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testProBlockAndDiscountWhereProIsOffered() {
        let sections = WhatsNewSections(showsPro: true, offer: offer)
        XCTAssertTrue(sections.showsProFeatures)
        XCTAssertEqual(sections.discount, offer)
    }

    func testProBlockWithoutDiscountWhenNoneRuns() {
        let sections = WhatsNewSections(showsPro: true, offer: nil)
        XCTAssertTrue(sections.showsProFeatures)
        XCTAssertNil(sections.discount)
    }

    func testNeitherWhereProIsNotOffered() {
        for given in [offer, nil] as [UpdateOffer?] {
            let sections = WhatsNewSections(showsPro: false, offer: given)
            XCTAssertFalse(sections.showsProFeatures)
            XCTAssertNil(sections.discount)
        }
    }

    func testDiscountOnlyWhileTheOfferRuns() throws {
        defaults.set(try JSONEncoder().encode(offer), forKey: UpdateChecker.offerKey)
        let calendar = Calendar.current
        let lastDay = try XCTUnwrap(offer.lastDay(calendar: calendar))
        let during = lastDay.addingTimeInterval(12 * 60 * 60)
        let after = try XCTUnwrap(offer.end(calendar: calendar)).addingTimeInterval(1)

        let running = UpdateChecker(defaults: defaults, currentVersion: "1.1.1", now: { during })
        XCTAssertEqual(WhatsNewSections(showsPro: true, offer: running.offer).discount, offer)

        let over = UpdateChecker(defaults: defaults, currentVersion: "1.1.1", now: { after })
        XCTAssertNil(WhatsNewSections(showsPro: true, offer: over.offer).discount)

        let off = UpdateChecker(defaults: defaults, currentVersion: "1.1.1", now: { during })
        off.isEnabled = false
        XCTAssertNil(WhatsNewSections(showsPro: true, offer: off.offer).discount)
    }
}

final class ProjectLinkTests: XCTestCase {
    func testWebsiteFollowsTheInterfaceLanguage() {
        XCTAssertEqual(ProjectLink.website.url(language: "de").absoluteString, "https://erstgebaut.de/lidawake/de/")
        for language in ["en", "ru", "zh-Hans", nil] as [String?] {
            XCTAssertEqual(
                ProjectLink.website.url(language: language).absoluteString,
                "https://erstgebaut.de/lidawake/",
                "\(String(describing: language))"
            )
        }
    }

    func testSourceCodeIsTheRepository() {
        for language in ["en", "de", "ru", "zh-Hans", nil] as [String?] {
            XCTAssertEqual(
                ProjectLink.sourceCode.url(language: language).absoluteString,
                "https://github.com/Vladimir-Podgornyi/LidAwake"
            )
        }
    }

    func testEveryLinkIsHTTPS() {
        for link in ProjectLink.allCases {
            XCTAssertEqual(link.url(language: nil).scheme, "https", "\(link)")
        }
    }
}
