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

final class WhatsNewSelectionTests: XCTestCase {
    /// Out of order on purpose; the window sorts.
    private let history = ["1.4.0", "1.2.0", "1.6.0", "1.3.0", "1.5.0"]

    private func since(_ lastShown: String?, current: String = "1.6.0") -> WhatsNewSelection {
        .sinceLastShown(history: history, current: current, lastShown: lastShown)
    }

    func testOneMissedVersion() {
        XCTAssertEqual(since("1.5.0"), WhatsNewSelection(versions: ["1.6.0"], earlierCount: 0))
    }

    func testThreeMissedVersionsNewestFirst() {
        XCTAssertEqual(since("1.3.0"), WhatsNewSelection(versions: ["1.6.0", "1.5.0", "1.4.0"], earlierCount: 0))
    }

    func testFiveMissedVersionsShowThreeAndCountTheRest() {
        let selection = since("1.1.0")
        XCTAssertEqual(selection.versions, ["1.6.0", "1.5.0", "1.4.0"])
        XCTAssertEqual(selection.earlierCount, 2)
    }

    func testFirstInstallShowsOnlyTheCurrentVersion() {
        XCTAssertEqual(since(nil), WhatsNewSelection(versions: ["1.6.0"], earlierCount: 0))
    }

    func testSameVersionShowsOnlyItself() {
        XCTAssertEqual(since("1.6.0"), WhatsNewSelection(versions: ["1.6.0"], earlierCount: 0))
    }

    func testAnUnreadableOrLaterSavedVersionShowsOnlyTheCurrentOne() {
        XCTAssertEqual(since("garbage"), WhatsNewSelection(versions: ["1.6.0"]))
        XCTAssertEqual(since("2.0.0"), WhatsNewSelection(versions: ["1.6.0"]))
    }

    func testVersionsAfterTheCurrentOneAreLeftOut() {
        XCTAssertEqual(since("1.2.0", current: "1.4.0"), WhatsNewSelection(versions: ["1.4.0", "1.3.0"]))
    }

    func testVersionsCompareAsNumbers() {
        let selection = WhatsNewSelection.sinceLastShown(
            history: ["1.9.0", "1.10.0", "1.8.0"], current: "1.10.0", lastShown: "1.8.0"
        )
        XCTAssertEqual(selection.versions, ["1.10.0", "1.9.0"])
    }

    func testCurrentVersionIsShownEvenWithoutAnEntry() {
        let selection = WhatsNewSelection.sinceLastShown(history: ["1.2.0"], current: "1.3.0", lastShown: "1.1.0")
        XCTAssertEqual(selection.versions, ["1.3.0", "1.2.0"])
    }

    func testFromTheRowTheCurrentVersionAndTwoBefore() {
        XCTAssertEqual(
            WhatsNewSelection.recent(history: history, current: "1.6.0"),
            WhatsNewSelection(versions: ["1.6.0", "1.5.0", "1.4.0"], earlierCount: 0)
        )
        XCTAssertEqual(
            WhatsNewSelection.recent(history: ["1.2.0"], current: "1.2.0"),
            WhatsNewSelection(versions: ["1.2.0"])
        )
    }

    func testLastShownVersionIsReadBack() throws {
        let suiteName = "WhatsNewSelectionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launch = WhatsNewLaunch(defaults: defaults)
        XCTAssertNil(launch.lastShownVersion)
        launch.markShown(version: "1.2.0")
        XCTAssertEqual(launch.lastShownVersion, "1.2.0")
    }
}

final class PicturePaletteTests: XCTestCase {
    /// The window and the tiles, light and dark.
    private let backgrounds = ThemedRGB(light: 0xFFFFFF, dark: 0x1E1E1E)

    func testSecondaryTextKeepsFourAndAHalfToOne() {
        for isDark in [false, true] {
            let ratio = Contrast.ratio(PicturePalette.secondaryText.value(isDark: isDark), backgrounds.value(isDark: isDark))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "dark: \(isDark)")
        }
    }

    func testBadgeTextKeepsFourAndAHalfToOneOnEveryFixedAccent() throws {
        for theme in [AccentTheme.blue, .amber] {
            let accent = try XCTUnwrap(theme.color)
            for isDark in [false, true] {
                let background = accent.value(isDark: isDark)
                let ratio = Contrast.ratio(PicturePalette.text(on: background), background)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme) dark: \(isDark)")
            }
        }
    }

    func testWaitBarsAreAmberWhateverTheAppearance() {
        XCTAssertEqual(PicturePalette.waitBar, ThemedRGB(light: 0xE8A33A, dark: 0xE8A33A))
    }
}
