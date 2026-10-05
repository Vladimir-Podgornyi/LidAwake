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

    func testChoiceDoesNotTouchSafetySettings() {
        let safety = SafetyPreferences(defaults: defaults)
        let before = safety.helperSettings
        var fired = false
        let subscription = safety.changes.sink { fired = true }
        let preference = SettingsDisclosurePreference(defaults: defaults)
        preference.isExpanded = true
        preference.isExpanded = false
        XCTAssertFalse(fired)
        XCTAssertEqual(SafetyPreferences(defaults: defaults).helperSettings, before)
        subscription.cancel()
    }
}

final class WindowBlockTests: XCTestCase {
    func testOffAndLidClosedCollapsed() {
        for mode in [Mode.off, .lidClosed] {
            for appearance in [false, true] {
                XCTAssertEqual(
                    WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: appearance),
                    [.settingsToggle, .closingDivider],
                    "\(mode)"
                )
            }
        }
    }

    func testOffAndLidClosedExpanded() {
        for mode in [Mode.off, .lidClosed] {
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true),
                [.settingsToggle, .safety, .settingsDivider, .lockScreen, .launchAtLogin, .checkForUpdates, .appearance, .accent, .closingDivider],
                "\(mode)"
            )
            XCTAssertEqual(
                WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: false),
                [.settingsToggle, .safety, .settingsDivider, .lockScreen, .launchAtLogin, .checkForUpdates, .accent, .closingDivider],
                "\(mode)"
            )
        }
    }

    func testKeepScreenOnCollapsedKeepsTheTimer() {
        for appearance in [false, true] {
            XCTAssertEqual(
                WindowBlock.list(mode: .keepScreenOn, isExpanded: false, showsAppearance: appearance),
                [.timer, .settingsToggle, .closingDivider]
            )
        }
    }

    func testKeepScreenOnExpanded() {
        XCTAssertEqual(
            WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: true),
            [.timer, .settingsToggle, .dimmedSafety, .settingsDivider, .launchAtLogin, .checkForUpdates, .appearance, .accent, .closingDivider]
        )
        XCTAssertEqual(
            WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: false),
            [.timer, .settingsToggle, .dimmedSafety, .settingsDivider, .launchAtLogin, .checkForUpdates, .accent, .closingDivider]
        )
    }

    func testBlocksAreUnique() {
        for mode in Mode.allCases {
            for expanded in [false, true] {
                let blocks = WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: true)
                XCTAssertEqual(Set(blocks).count, blocks.count)
            }
        }
    }
}
