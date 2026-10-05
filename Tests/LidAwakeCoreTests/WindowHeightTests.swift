import XCTest
@testable import LidAwakeCore

final class WindowHeightLimitTests: XCTestCase {
    /// A MacBook Air screen, 1440 x 900, with the menu bar taking 33 points and the Dock hidden.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 867)

    private func geometry(top: CGFloat, height: CGFloat, chrome: CGFloat = 0) -> WindowGeometry {
        WindowGeometry(
            visibleFrame: visible,
            windowFrame: CGRect(x: 1000, y: top - height, width: 320, height: height),
            contentHeight: height - chrome
        )
    }

    func testLimitStartsAtTheWindowTop() {
        // The window starts 6 points below the menu bar.
        XCTAssertEqual(WindowHeightLimit.maxContentHeight(geometry(top: 861, height: 400)), 849)
    }

    func testLimitLeavesRoomForTheChrome() {
        XCTAssertEqual(WindowHeightLimit.maxContentHeight(geometry(top: 861, height: 400, chrome: 10)), 839)
    }

    func testLimitCountsFromTheVisibleBottom() {
        let raised = WindowGeometry(
            visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 797),
            windowFrame: CGRect(x: 1000, y: 461, width: 320, height: 400),
            contentHeight: 400
        )
        XCTAssertEqual(WindowHeightLimit.maxContentHeight(raised), 779)
    }

    func testBottomGap() {
        XCTAssertEqual(geometry(top: 861, height: 849).bottomGap, 12)
        XCTAssertEqual(geometry(top: 861, height: 870).bottomGap, -9)
    }

    func testOldEstimateLetTheWindowReachTheBottom() {
        // Visible height minus 16 was 851; from a top at 861 with 4 points of chrome that
        // leaves 6 points instead of 12.
        let window = geometry(top: 861, height: 855, chrome: 4)
        XCTAssertEqual(window.bottomGap, 6)
        XCTAssertEqual(WindowHeightLimit.maxContentHeight(window), 845)
    }

    func testNoLimitNeverScrolls() {
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 5000, maxHeight: nil))
    }

    func testContentThatFitsDoesNotScroll() {
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 400, maxHeight: 851))
        XCTAssertNil(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 551, maxHeight: 851))
    }

    func testTallContentScrollsBelowTheFixedPart() {
        XCTAssertEqual(WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 552, maxHeight: 851), 551)
        XCTAssertEqual(WindowHeightLimit.scrollHeight(fixedHeight: 290, contentHeight: 600, maxHeight: 600), 310)
    }

    func testScrollingPartKeepsAMinimumOnTinyScreens() {
        XCTAssertEqual(
            WindowHeightLimit.scrollHeight(fixedHeight: 300, contentHeight: 600, maxHeight: 350),
            WindowHeightLimit.minimumScrollHeight
        )
    }
}

final class WindowFitTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 867)

    private func geometry(top: CGFloat, height: CGFloat, content: CGFloat) -> WindowGeometry {
        WindowGeometry(
            visibleFrame: visible,
            windowFrame: CGRect(x: 1000, y: top - height, width: 320, height: height),
            contentHeight: content
        )
    }

    func testFirstLookFollowsTheGeometry() {
        var fit = WindowFit()
        // Opened at its natural height, too tall for the screen: no correction yet.
        XCTAssertEqual(fit.update(geometry(top: 861, height: 1000, content: 1000)), 849)
        XCTAssertEqual(fit.correction, 0)
    }

    func testWindowWithinTheMarginNeedsNoCorrection() {
        var fit = WindowFit()
        fit.update(geometry(top: 861, height: 1000, content: 1000))
        XCTAssertEqual(fit.update(geometry(top: 861, height: 849, content: 849)), 849)
        XCTAssertEqual(fit.correction, 0)
    }

    func testWindowStillTooLowLowersTheLimit() {
        var fit = WindowFit()
        fit.update(geometry(top: 861, height: 1000, content: 1000))
        // Laid out within 849, yet the frame ends 5 points above the bottom, for example
        // because the window was moved down after resizing.
        XCTAssertEqual(fit.update(geometry(top: 854, height: 849, content: 849)), 835)
        XCTAssertEqual(fit.correction, 7)
        // Laid out within the new limit, the bottom is 12 points clear: stays put.
        XCTAssertEqual(fit.update(geometry(top: 854, height: 835, content: 835)), 835)
        XCTAssertEqual(fit.correction, 7)
    }

    func testCorrectionHasACeiling() {
        var fit = WindowFit()
        fit.update(geometry(top: 861, height: 400, content: 400))
        for _ in 0..<50 {
            let limit = fit.limit ?? 0
            fit.update(geometry(top: limit - 100, height: limit, content: limit))
        }
        XCTAssertEqual(fit.correction, WindowFit.maxCorrection)
    }

    func testResetStartsOver() {
        var fit = WindowFit()
        fit.update(geometry(top: 861, height: 1000, content: 1000))
        fit.update(geometry(top: 854, height: 849, content: 849))
        fit.reset()
        XCTAssertEqual(fit.correction, 0)
        XCTAssertNil(fit.limit)
    }

    func testReportLine() {
        let line = WindowGeometryReport.line(
            WindowGeometry(
                visibleFrame: visible,
                windowFrame: CGRect(x: 1061.5, y: 12, width: 320, height: 849),
                contentHeight: 849
            ),
            limit: 849,
            isScrolling: true
        )
        XCTAssertEqual(
            line,
            "visible=0,0,1440,867 frame=1061.5,12,320,849 content-height=849 limit=849 scrolls=yes bottom-gap=12"
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
