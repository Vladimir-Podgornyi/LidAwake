import Combine
import XCTest
@testable import LidAwakeCore

@MainActor
final class SettingsDisclosurePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsDisclosureTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCollapsedWithoutStoredValue() {
        XCTAssertFalse(SettingsDisclosurePreference(defaults: defaults).isExpanded)
    }

    func testStoredValueIsRead() {
        defaults.set(true, forKey: "settingsExpanded")
        XCTAssertTrue(SettingsDisclosurePreference(defaults: defaults).isExpanded)
        defaults.set(false, forKey: "settingsExpanded")
        XCTAssertFalse(SettingsDisclosurePreference(defaults: defaults).isExpanded)
    }

    func testChoiceIsStored() {
        let preference = SettingsDisclosurePreference(defaults: defaults)
        preference.isExpanded = true
        XCTAssertEqual(defaults.object(forKey: "settingsExpanded") as? Bool, true)
        XCTAssertTrue(SettingsDisclosurePreference(defaults: defaults).isExpanded)
        preference.isExpanded = false
        XCTAssertEqual(defaults.object(forKey: "settingsExpanded") as? Bool, false)
        XCTAssertFalse(SettingsDisclosurePreference(defaults: defaults).isExpanded)
    }

    func testSectionsExpandedWithoutStoredValue() {
        let preference = SettingsDisclosurePreference(defaults: defaults)
        XCTAssertTrue(preference.isSleepAndWakeExpanded)
        XCTAssertTrue(preference.isGeneralExpanded)
    }

    func testSectionChoicesAreStoredApart() {
        let preference = SettingsDisclosurePreference(defaults: defaults)
        preference.isSleepAndWakeExpanded = false
        XCTAssertEqual(defaults.object(forKey: "sleepAndWakeExpanded") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "generalExpanded"))
        XCTAssertNil(defaults.object(forKey: "settingsExpanded"))
        var reread = SettingsDisclosurePreference(defaults: defaults)
        XCTAssertFalse(reread.isSleepAndWakeExpanded)
        XCTAssertTrue(reread.isGeneralExpanded)
        XCTAssertFalse(reread.isExpanded)

        preference.isGeneralExpanded = false
        preference.isSleepAndWakeExpanded = true
        XCTAssertEqual(defaults.object(forKey: "generalExpanded") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "sleepAndWakeExpanded") as? Bool, true)
        reread = SettingsDisclosurePreference(defaults: defaults)
        XCTAssertTrue(reread.isSleepAndWakeExpanded)
        XCTAssertFalse(reread.isGeneralExpanded)
    }

    func testSettingsChoiceLeavesTheSectionsAlone() {
        let preference = SettingsDisclosurePreference(defaults: defaults)
        preference.isGeneralExpanded = false
        preference.isExpanded = true
        preference.isExpanded = false
        let reread = SettingsDisclosurePreference(defaults: defaults)
        XCTAssertTrue(reread.isSleepAndWakeExpanded)
        XCTAssertFalse(reread.isGeneralExpanded)
    }

    func testChoiceDoesNotTouchSafetySettings() {
        let safety = SafetyPreferences(defaults: defaults)
        let before = safety.helperSettings
        var fired = false
        let subscription = safety.changes.sink { fired = true }
        let preference = SettingsDisclosurePreference(defaults: defaults)
        preference.isExpanded = true
        preference.isExpanded = false
        preference.isSleepAndWakeExpanded = false
        preference.isGeneralExpanded = false
        XCTAssertFalse(fired)
        XCTAssertEqual(SafetyPreferences(defaults: defaults).helperSettings, before)
        subscription.cancel()
    }
}

final class WindowBlockTests: XCTestCase {
    private let bottom: [WindowBlock] = [.closingDivider, .whatsNew, .howToUse, .quit]

    func testOffAndLidClosedCollapsed() {
        for mode in [Mode.off, .lidClosed] {
            for appearance in [false, true] {
                XCTAssertEqual(
                    WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: appearance),
                    [.settingsToggle] + bottom,
                    "\(mode)"
                )
            }
        }
    }

    func testOffAndLidClosedExpanded() {
        for mode in [Mode.off, .lidClosed] {
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true),
                [.settingsToggle, .safety, .sleepAndWake, .settingsDivider, .generalHeader, .lockScreen, .launchAtLogin, .checkForUpdates, .appearance, .accent, .activityLog] + bottom,
                "\(mode)"
            )
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: false),
                [.settingsToggle, .safety, .sleepAndWake, .settingsDivider, .generalHeader, .lockScreen, .launchAtLogin, .checkForUpdates, .accent, .activityLog] + bottom,
                "\(mode)"
            )
        }
    }

    func testKeepScreenOnCollapsedKeepsTheTimer() {
        for appearance in [false, true] {
            XCTAssertEqual(
                WindowBlock.list(mode: .keepScreenOn, isExpanded: false, showsAppearance: appearance),
                [.timer, .settingsToggle] + bottom
            )
        }
    }

    func testKeepScreenOnExpanded() {
        XCTAssertEqual(
            WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: true),
            [.timer, .settingsToggle, .dimmedSafety, .sleepAndWake, .settingsDivider, .generalHeader, .launchAtLogin, .checkForUpdates, .appearance, .accent, .activityLog] + bottom
        )
        XCTAssertEqual(
            WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: false),
            [.timer, .settingsToggle, .dimmedSafety, .sleepAndWake, .settingsDivider, .generalHeader, .launchAtLogin, .checkForUpdates, .accent, .activityLog] + bottom
        )
    }

    func testActivityLogIsTheLastGeneralRowInEveryPosition() {
        for mode in Mode.allCases {
            for appearance in [false, true] {
                let blocks = WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: appearance)
                XCTAssertEqual(Array(blocks.suffix(6)), [.accent, .activityLog] + bottom, "\(mode)")
                XCTAssertEqual(blocks.filter(\.isGeneralSettingRow).last, .activityLog, "\(mode)")
            }
        }
    }

    func testProOfferIsTheFirstBlockAboveTheSettingsWhenShown() {
        for mode in Mode.allCases {
            let timer: [WindowBlock] = SafetyLayout(mode: mode) == .timerOnly ? [.timer] : []
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true, showsProOffer: true),
                [.proOffer] + timer + [.settingsToggle] + bottom,
                "\(mode)"
            )
            for expanded in [false, true] {
                for appearance in [false, true] {
                    for general in [false, true] {
                        let with = WindowBlock.list(
                            mode: mode,
                            isExpanded: expanded,
                            showsAppearance: appearance,
                            showsProOffer: true,
                            isGeneralExpanded: general
                        )
                        XCTAssertEqual(with.first, .proOffer, "\(mode)")
                        XCTAssertEqual(Array(with.prefix(timer.count + 2)), [.proOffer] + timer + [.settingsToggle], "\(mode)")
                        XCTAssertLessThan(with.firstIndex(of: .proOffer)!, with.firstIndex(of: .settingsToggle)!, "\(mode)")
                    }
                }
            }
            let expanded = WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true, showsProOffer: true)
            XCTAssertEqual(Array(expanded.suffix(6)), [.accent, .activityLog] + bottom, "\(mode)")
            XCTAssertEqual(expanded.filter(\.isGeneralSettingRow).last, .activityLog, "\(mode)")
        }
    }

    func testWithoutProOfferTheBlocksStayAsBefore() {
        for mode in Mode.allCases {
            let timer: [WindowBlock] = SafetyLayout(mode: mode) == .timerOnly ? [.timer] : []
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true),
                timer + [.settingsToggle] + bottom,
                "\(mode)"
            )
            for expanded in [false, true] {
                for appearance in [false, true] {
                    let without = WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: appearance)
                    let with = WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: appearance, showsProOffer: true)
                    XCTAssertFalse(without.contains(.proOffer), "\(mode)")
                    XCTAssertEqual(with.filter { $0 != .proOffer }, without, "\(mode)")
                    XCTAssertEqual(
                        without,
                        WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: appearance, showsProOffer: false),
                        "\(mode)"
                    )
                }
            }
        }
    }

    func testProOfferIsNotAGeneralSettingRow() {
        XCTAssertFalse(WindowBlock.proOffer.isGeneralSettingRow)
    }

    func testWhatsNewHowToUseAndQuitEndTheWindowInEveryPosition() {
        for mode in Mode.allCases {
            for expanded in [false, true] {
                for appearance in [false, true] {
                    for proOffer in [false, true] {
                        let blocks = WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: appearance, showsProOffer: proOffer)
                        XCTAssertEqual(Array(blocks.suffix(4)), bottom, "\(mode) \(expanded) \(proOffer)")
                        XCTAssertEqual(blocks.filter(bottom.contains), bottom, "each once, \(mode) \(expanded) \(proOffer)")
                    }
                }
            }
        }
    }

    func testBottomRowsAreNotGeneralSettings() {
        for block in [WindowBlock.whatsNew, .howToUse, .quit] {
            XCTAssertFalse(block.isGeneralSettingRow, "\(block)")
            XCTAssertTrue(block.isCompactRow, "\(block)")
        }
    }

    func testActivityLogCollapsesWithTheSettings() {
        for mode in Mode.allCases {
            XCTAssertFalse(WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true).contains(.activityLog))
        }
    }

    func testSleepAndWakeSitsBetweenSafetyAndGeneralInEveryPosition() {
        for mode in Mode.allCases {
            let blocks = WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true)
            let safety = SafetyLayout(mode: mode) == .all ? WindowBlock.safety : .dimmedSafety
            let order = [safety, .sleepAndWake, .settingsDivider, .generalHeader]
            XCTAssertEqual(blocks.filter(order.contains), order, "\(mode)")
            XCTAssertEqual(blocks.firstIndex(of: .generalHeader).map { $0 + 1 }, blocks.firstIndex(where: \.isGeneralSettingRow), "\(mode)")
        }
    }

    func testLockScreenIsTheFirstGeneralRowOnlyWhereTheLidMatters() {
        for mode in [Mode.off, .lidClosed] {
            let blocks = WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true)
            XCTAssertEqual(blocks.filter(\.isGeneralSettingRow).first, .lockScreen, "\(mode)")
        }
        let screen = WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: true)
        XCTAssertEqual(screen.filter(\.isGeneralSettingRow).first, .launchAtLogin)
        XCTAssertFalse(screen.contains(.lockScreen), "the lock stays in the dimmed section")
    }

    func testNewSectionsCollapseWithTheSettings() {
        for mode in Mode.allCases {
            let blocks = WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true)
            XCTAssertFalse(blocks.contains(.sleepAndWake), "\(mode)")
            XCTAssertFalse(blocks.contains(.generalHeader), "\(mode)")
        }
    }

    func testCollapsedGeneralKeepsItsHeaderAndHidesItsRows() {
        for mode in Mode.allCases {
            for proOffer in [false, true] {
                let expanded = WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true, showsProOffer: proOffer)
                let collapsed = WindowBlock.list(
                    mode: mode,
                    isExpanded: true,
                    showsAppearance: true,
                    showsProOffer: proOffer,
                    isGeneralExpanded: false
                )
                XCTAssertEqual(collapsed, expanded.filter { !$0.isGeneralSettingRow }, "\(mode)")
                XCTAssertFalse(collapsed.contains(where: \.isGeneralSettingRow), "\(mode)")
                XCTAssertTrue(collapsed.contains(.generalHeader), "\(mode)")
                XCTAssertTrue(collapsed.contains(.sleepAndWake), "\(mode)")
                XCTAssertTrue(collapsed.contains(SafetyLayout(mode: mode) == .all ? .safety : .dimmedSafety), "\(mode)")
                XCTAssertEqual(Array(collapsed.suffix(4)), bottom, "\(mode)")
            }
        }
    }

    func testGeneralChoiceDoesNothingWhileTheSettingsAreCollapsed() {
        for mode in Mode.allCases {
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true, isGeneralExpanded: false),
                WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true),
                "\(mode)"
            )
        }
    }

    func testBlocksAreUnique() {
        for mode in Mode.allCases {
            for expanded in [false, true] {
                for proOffer in [false, true] {
                    for general in [false, true] {
                        let blocks = WindowBlock.list(
                            mode: mode,
                            isExpanded: expanded,
                            showsAppearance: true,
                            showsProOffer: proOffer,
                            isGeneralExpanded: general
                        )
                        XCTAssertEqual(Set(blocks).count, blocks.count)
                    }
                }
            }
        }
    }
}

final class ProOfferLinkTests: XCTestCase {
    func testGermanInterfaceOpensTheGermanPage() {
        XCTAssertEqual(ProOfferLink.page(language: "de").absoluteString, "https://erstgebaut.de/lidawake/de/")
    }

    func testOtherLanguagesOpenTheMainPage() {
        for language in ["en", "ru", "zh-Hans", "de-AT", "", nil] as [String?] {
            XCTAssertEqual(ProOfferLink.page(language: language).absoluteString, "https://erstgebaut.de/lidawake/", "\(String(describing: language))")
        }
    }
}
