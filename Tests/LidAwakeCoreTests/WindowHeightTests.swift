import XCTest
@testable import LidAwakeCore

final class WindowHeightLimitTests: XCTestCase {
    func testMaxWindowHeightLeavesAMarginBelow() {
        // A MacBook Air: 900 points, of which the menu bar takes 33.
        XCTAssertEqual(WindowHeightLimit.maxWindowHeight(visibleScreenHeight: 867), 851)
        XCTAssertEqual(WindowHeightLimit.maxWindowHeight(visibleScreenHeight: 10), 0)
    }

    func testNoLimitNeverScrolls() {
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 5000, maxWindowHeight: nil))
    }

    func testContentThatFitsDoesNotScroll() {
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 400, maxWindowHeight: 851))
    }

    func testContentThatFitsExactlyDoesNotScroll() {
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 551, maxWindowHeight: 851))
    }

    func testTallContentScrollsBelowTheFixedPart() {
        XCTAssertEqual(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 552, maxWindowHeight: 851), 551)
        XCTAssertEqual(WindowHeightLimit.scrollHeight(fixedHeight: 290, contentHeight: 600, maxWindowHeight: 600), 310)
    }

    func testScrollingPartKeepsAMinimumOnTinyScreens() {
        XCTAssertEqual(
            WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 600, maxWindowHeight: 350),
            WindowHeightLimit.minimumScrollHeight
        )
    }
}

final class WindowBlockGroupTests: XCTestCase {
    func testCollapsedHasNoCompactRows() {
        for mode in Mode.allCases {
            let blocks = WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true)
            XCTAssertEqual(WindowBlockGroup.groups(blocks), blocks.map(WindowBlockGroup.block))
        }
    }

    func testOffExpandedGroupsTheGeneralRowsWithTheirDividers() {
        let blocks = WindowBlock.list(mode: .off, isExpanded: true, showsAppearance: true)
        XCTAssertEqual(WindowBlockGroup.groups(blocks), [
            .block(.settingsToggle),
            .block(.safety),
            .compactRows([.settingsDivider, .lockScreen, .launchAtLogin, .checkForUpdates, .appearance, .accent, .closingDivider]),
        ])
    }

    func testKeepScreenOnExpandedLeavesTheDimmedSectionApart() {
        let blocks = WindowBlock.list(mode: .keepScreenOn, isExpanded: true, showsAppearance: false)
        XCTAssertEqual(WindowBlockGroup.groups(blocks), [
            .block(.timer),
            .block(.settingsToggle),
            .block(.dimmedSafety),
            .compactRows([.settingsDivider, .launchAtLogin, .checkForUpdates, .accent, .closingDivider]),
        ])
    }

    func testGroupsKeepEveryBlockInOrder() {
        for mode in Mode.allCases {
            for expanded in [false, true] {
                for appearance in [false, true] {
                    let blocks = WindowBlock.list(mode: mode, isExpanded: expanded, showsAppearance: appearance)
                    let flattened = WindowBlockGroup.groups(blocks).flatMap { group -> [WindowBlock] in
                        switch group {
                        case .block(let block): return [block]
                        case .compactRows(let rows): return rows
                        }
                    }
                    XCTAssertEqual(flattened, blocks)
                }
            }
        }
    }
}
