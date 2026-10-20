import Combine
import LidAwakeShared
import XCTest
@testable import LidAwakeCore

final class SleepAndWakeRowTests: XCTestCase {
    func testWatchedAppsIsTheThirdRowInEveryPosition() {
        XCTAssertEqual(SleepAndWakeRow.list(mode: .off), [.wakeAt, .sleepWhenIdle(isDimmed: false), .watchedApps])
        XCTAssertEqual(SleepAndWakeRow.list(mode: .lidClosed), [.wakeAt, .sleepWhenIdle(isDimmed: false), .watchedApps])
        XCTAssertEqual(SleepAndWakeRow.list(mode: .keepScreenOn), [.wakeAt, .sleepWhenIdle(isDimmed: true), .watchedApps])
    }

    func testWatchedAppsSitsInTheExpandedSleepAndWakeSection() {
        for mode in Mode.allCases {
            XCTAssertTrue(WindowBlock.list(mode: mode, isExpanded: true, showsAppearance: true).contains(.sleepAndWake))
            XCTAssertFalse(WindowBlock.list(mode: mode, isExpanded: false, showsAppearance: true).contains(.sleepAndWake))
        }
    }
}

final class WatchedAppsSummaryTests: XCTestCase {
    private func name(_ path: String) -> String {
        WatchedApps.name(ofAppAt: path)
    }

    func testNoneWhenNothingIsChosen() {
        XCTAssertEqual(WatchedAppsSummary.text(paths: [], name: name), "None")
    }

    func testOneApp() {
        XCTAssertEqual(WatchedAppsSummary.text(paths: ["/Applications/Editor.app"], name: name), "Editor")
    }

    func testSeveralAppsInTheChosenOrder() {
        XCTAssertEqual(
            WatchedAppsSummary.text(paths: ["/Applications/Shell.app", "/Applications/Editor.app", "/Users/me/Apps/Builder.app"], name: name),
            "Shell, Editor, Builder"
        )
    }

    func testTheNameComesFromTheGivenFunction() {
        XCTAssertEqual(
            WatchedAppsSummary.text(paths: ["/Applications/Editor.app"], name: { _ in "Shown Name" }),
            "Shown Name"
        )
    }
}

final class WatchedAppListTests: XCTestCase {
    private func app(_ name: String, regular: Bool = true, id: String? = nil, path: String? = nil) -> RunningApp {
        RunningApp(
            path: path ?? "/Applications/\(name).app",
            name: name,
            bundleIdentifier: id ?? "example.\(name.lowercased())",
            isRegular: regular
        )
    }

    private func make(_ running: [RunningApp], watched: [String] = []) -> WatchedAppList {
        WatchedAppList.make(
            running: running,
            watched: watched,
            ownBundleIdentifier: "com.vladimirpodgornyi.LidAwake",
            ownPath: "/Applications/LidAwake.app",
            name: { "Named " + WatchedApps.name(ofAppAt: $0) }
        )
    }

    func testOpenAppsAreSortedByName() {
        let list = make([app("Shell"), app("editor"), app("Builder"), app("Zed Notes")])
        XCTAssertEqual(list.open.map(\.name), ["Builder", "editor", "Shell", "Zed Notes"])
        XCTAssertEqual(list.notOpen, [])
    }

    func testNumbersInNamesSortAsNumbers() {
        XCTAssertEqual(make([app("Tool 10"), app("Tool 9")]).open.map(\.name), ["Tool 9", "Tool 10"])
    }

    func testBackgroundAppsAreLeftOut() {
        let list = make([app("Editor"), app("Agent", regular: false)])
        XCTAssertEqual(list.open.map(\.name), ["Editor"])
    }

    func testLidAwakeIsLeftOutByIdentifierAndByPath() {
        let list = make([
            app("Editor"),
            app("LidAwake", id: "com.vladimirpodgornyi.LidAwake", path: "/Users/me/Build/LidAwake.app"),
            app("LidAwake Copy", id: nil, path: "/Applications/LidAwake.app"),
        ])
        XCTAssertEqual(list.open.map(\.name), ["Editor"])
        XCTAssertEqual(make([app("Editor")], watched: ["/Applications/LidAwake.app"]).notOpen, [])
    }

    func testAppsOutsideBundlesAreLeftOut() {
        let list = make([app("Editor"), app("tool", path: "/usr/local/bin/tool")])
        XCTAssertEqual(list.open.map(\.name), ["Editor"])
    }

    func testTwoCopiesOfOneAppAreOneRow() {
        XCTAssertEqual(make([app("Editor"), app("Editor")]).open.count, 1)
    }

    func testWatchedOpenAppsAreMarked() {
        let list = make([app("Editor"), app("Shell")], watched: ["/Applications/Shell.app"])
        XCTAssertEqual(list.open.map(\.isWatched), [false, true])
    }

    func testWatchedAppsThatAreNotOpenAreListedApartByName() {
        let list = make(
            [app("Editor")],
            watched: ["/Applications/Studio.app", "/Applications/Editor.app", "/Applications/Builder.app"]
        )
        XCTAssertEqual(list.open.map(\.name), ["Editor"])
        XCTAssertEqual(list.notOpen.map(\.name), ["Named Builder", "Named Studio"])
        XCTAssertTrue(list.notOpen.allSatisfy(\.isWatched))
    }

    func testAWatchedAppRunningInTheBackgroundIsNotOpen() {
        let list = make([app("Agent", regular: false)], watched: ["/Applications/Agent.app"])
        XCTAssertEqual(list.open, [])
        XCTAssertEqual(list.notOpen.map(\.path), ["/Applications/Agent.app"])
    }

    func testAnEmptyNameFallsBackToTheFolder() {
        XCTAssertEqual(make([app("", path: "/Applications/Editor.app")]).open.map(\.name), ["Named Editor"])
    }
}

final class WatchedAppSelectionTests: XCTestCase {
    func testTurningOnAddsAtTheEndOnce() {
        let paths = ["/Applications/Editor.app"]
        XCTAssertEqual(
            WatchedAppSelection.setting("/Applications/Shell.app", isOn: true, in: paths),
            ["/Applications/Editor.app", "/Applications/Shell.app"]
        )
        XCTAssertEqual(WatchedAppSelection.setting("/Applications/Editor.app", isOn: true, in: paths), paths)
    }

    func testTurningOffRemoves() {
        XCTAssertEqual(
            WatchedAppSelection.setting("/Applications/Editor.app", isOn: false, in: ["/Applications/Editor.app", "/Applications/Shell.app"]),
            ["/Applications/Shell.app"]
        )
    }

    func testOnlyAppsAreAdded() {
        XCTAssertEqual(WatchedAppSelection.setting("/usr/local/bin/tool", isOn: true, in: []), [])
    }

    func testAFullListTakesNoMore() {
        let full = (1...WatchedApps.maximumCount).map { "/Applications/App \($0).app" }
        XCTAssertFalse(WatchedAppSelection.canAdd(to: full))
        XCTAssertTrue(WatchedAppSelection.canAdd(to: Array(full.dropLast())))
        XCTAssertEqual(WatchedAppSelection.setting("/Applications/Editor.app", isOn: true, in: full), full)
    }

    func testSpaceFlipsTheApp() {
        let paths = ["/Applications/Editor.app"]
        XCTAssertEqual(
            WatchedAppSelection.toggling("/Applications/Shell.app", in: paths),
            ["/Applications/Editor.app", "/Applications/Shell.app"]
        )
        XCTAssertEqual(WatchedAppSelection.toggling("/Applications/Editor.app", in: paths), [])
    }

    func testSpaceOnAFullListOnlyTurnsOff() {
        let full = (1...WatchedApps.maximumCount).map { "/Applications/App \($0).app" }
        XCTAssertEqual(WatchedAppSelection.toggling("/Applications/Editor.app", in: full), full)
        XCTAssertEqual(WatchedAppSelection.toggling(full[3], in: full), full.filter { $0 != full[3] })
    }
}

final class WatchedAppCursorTests: XCTestCase {
    private let rows = ["/Applications/A.app", "/Applications/B.app", "/Applications/C.app", "/Applications/D.app"]

    func testRowsRunThroughBothSectionsWithoutHeadings() {
        let list = WatchedAppList(
            open: [
                WatchedAppEntry(path: "/Applications/B.app", name: "B", isWatched: false),
                WatchedAppEntry(path: "/Applications/C.app", name: "C", isWatched: true),
            ],
            notOpen: [WatchedAppEntry(path: "/Applications/A.app", name: "A", isWatched: true)]
        )
        XCTAssertEqual(list.rowPaths, ["/Applications/B.app", "/Applications/C.app", "/Applications/A.app"])
    }

    func testNothingIsChosenUntilTheListGetsTheKeys() {
        var cursor = WatchedAppCursor(rows: rows)
        XCTAssertNil(cursor.selected)
        cursor.enter()
        XCTAssertEqual(cursor.selected, rows[0])
    }

    func testComingBackKeepsTheRowChosenBefore() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[2])
        cursor.enter()
        XCTAssertEqual(cursor.selected, rows[2])
    }

    func testAnEmptyListHasNoRowToChoose() {
        var cursor = WatchedAppCursor()
        cursor.enter()
        cursor.move(by: 1)
        XCTAssertNil(cursor.selected)
    }

    func testArrowsMoveOneRowAndStopAtTheEnds() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[0])
        cursor.move(by: -1)
        XCTAssertEqual(cursor.selected, rows[0])
        cursor.move(by: 1)
        XCTAssertEqual(cursor.selected, rows[1])
        cursor.move(by: 1)
        cursor.move(by: 1)
        cursor.move(by: 1)
        XCTAssertEqual(cursor.selected, rows[3])
        cursor.move(by: -1)
        XCTAssertEqual(cursor.selected, rows[2])
    }

    func testAnArrowWithNothingChosenChoosesTheFirstRow() {
        var cursor = WatchedAppCursor(rows: rows)
        cursor.move(by: 1)
        XCTAssertEqual(cursor.selected, rows[0])
    }

    func testTheChoiceFollowsItsAppWhenTheListChanges() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[1])
        // An app opened above it, and the chosen app moved from one section to the other.
        cursor.update(rows: ["/Applications/0.app", rows[0], rows[2], rows[3], rows[1]])
        XCTAssertEqual(cursor.selected, rows[1])
    }

    func testTheSameListKeepsTheChoice() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[2])
        cursor.update(rows: rows)
        XCTAssertEqual(cursor.selected, rows[2])
        XCTAssertEqual(cursor.rows, rows)
    }

    func testAClosedAppPassesTheChoiceToTheNextRow() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[1])
        cursor.update(rows: [rows[0], rows[2], rows[3]])
        XCTAssertEqual(cursor.selected, rows[2])
    }

    func testTheNextRowThatIsStillThereIsChosen() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[1])
        cursor.update(rows: [rows[0], rows[3]])
        XCTAssertEqual(cursor.selected, rows[3])
    }

    func testTheLastRowPassesTheChoiceUp() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[3])
        cursor.update(rows: [rows[0], rows[1]])
        XCTAssertEqual(cursor.selected, rows[1])
    }

    func testAnEmptiedListHasNoChoice() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[0])
        cursor.update(rows: [])
        XCTAssertNil(cursor.selected)
    }

    func testNothingChosenStaysSoWhenTheListChanges() {
        var cursor = WatchedAppCursor(rows: rows)
        cursor.update(rows: Array(rows.dropFirst()))
        XCTAssertNil(cursor.selected)
    }

    func testClosingTheWindowForgetsTheChoice() {
        var cursor = WatchedAppCursor(rows: rows, selected: rows[2])
        cursor.reset()
        XCTAssertNil(cursor.selected)
        cursor.enter()
        XCTAssertEqual(cursor.selected, rows[0])
    }

    func testAChoiceOutsideTheRowsIsDropped() {
        XCTAssertNil(WatchedAppCursor(rows: rows, selected: "/Applications/Z.app").selected)
    }
}

final class WatchedAppsTurnedOffTests: XCTestCase {
    private let editor = "/Applications/Editor.app"
    private let shell = "/Applications/Shell.app"
    private let studio = "/Applications/Studio.app"

    private func app(_ path: String) -> RunningApp {
        RunningApp(path: path, name: WatchedApps.name(ofAppAt: path), bundleIdentifier: nil, isRegular: true)
    }

    private func make(_ running: [RunningApp] = [], watched: [String], turnedOff: WatchedAppsTurnedOff) -> WatchedAppList {
        WatchedAppList.make(
            running: running,
            watched: watched,
            turnedOff: turnedOff.paths,
            ownBundleIdentifier: "com.vladimirpodgornyi.LidAwake",
            ownPath: "/Applications/LidAwake.app",
            name: { WatchedApps.name(ofAppAt: $0) }
        )
    }

    func testAnAppTurnedOffInWatchedNotOpenKeepsItsRowSwitchedOff() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [studio, editor, shell]
        let before = make(watched: watched, turnedOff: turnedOff)
        let after = turnedOff.toggling(shell, in: watched, list: before)
        XCTAssertEqual(after, [studio, editor])
        let list = make(watched: after, turnedOff: turnedOff)
        XCTAssertEqual(list.rowPaths, before.rowPaths)
        XCTAssertEqual(list.notOpen.map(\.isWatched), [true, false, true])
    }

    func testAClickWorksLikeSpace() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor, shell]
        let after = turnedOff.setting(editor, isOn: false, in: watched, list: make(watched: watched, turnedOff: turnedOff))
        XCTAssertEqual(after, [shell])
        XCTAssertEqual(make(watched: after, turnedOff: turnedOff).notOpen.map(\.path), [editor, shell])
    }

    func testSpaceAgainTurnsItBackOn() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor, shell]
        let off = turnedOff.toggling(editor, in: watched, list: make(watched: watched, turnedOff: turnedOff))
        let on = turnedOff.toggling(editor, in: off, list: make(watched: off, turnedOff: turnedOff))
        XCTAssertEqual(on, [shell, editor])
        XCTAssertEqual(make(watched: on, turnedOff: turnedOff).notOpen.map(\.isWatched), [true, true])
    }

    func testAFullListDoesNotTakeItBack() {
        var turnedOff = WatchedAppsTurnedOff()
        let others = (1..<WatchedApps.maximumCount).map { "/Applications/App \($0).app" }
        let watched = others + [editor]
        let off = turnedOff.toggling(editor, in: watched, list: make(watched: watched, turnedOff: turnedOff))
        XCTAssertEqual(off, others)
        let full = WatchedAppSelection.setting(studio, isOn: true, in: off)
        XCTAssertFalse(WatchedAppSelection.canAdd(to: full))
        XCTAssertEqual(turnedOff.toggling(editor, in: full, list: make(watched: full, turnedOff: turnedOff)), full)
        XCTAssertEqual(turnedOff.setting(editor, isOn: true, in: full, list: make(watched: full, turnedOff: turnedOff)), full)
        let row = make(watched: full, turnedOff: turnedOff).notOpen.first { $0.path == editor }
        XCTAssertEqual(row?.isWatched, false)
    }

    func testTheRowIsGoneWhenTheWindowOpensAgain() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor, shell]
        let after = turnedOff.toggling(editor, in: watched, list: make(watched: watched, turnedOff: turnedOff))
        turnedOff.reset()
        XCTAssertEqual(make(watched: after, turnedOff: turnedOff).notOpen.map(\.path), [shell])
    }

    func testAnAppThatOpensMovesToOpenNow() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor]
        let after = turnedOff.toggling(editor, in: watched, list: make(watched: watched, turnedOff: turnedOff))
        let list = make([app(editor)], watched: after, turnedOff: turnedOff)
        XCTAssertEqual(list.open, [WatchedAppEntry(path: editor, name: "Editor", isWatched: false)])
        XCTAssertEqual(list.notOpen, [])
    }

    func testAnAppTurnedOffInOpenNowIsNotKept() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor]
        let list = make([app(editor)], watched: watched, turnedOff: turnedOff)
        XCTAssertEqual(turnedOff.toggling(editor, in: watched, list: list), [])
        XCTAssertEqual(turnedOff.paths, [])
        XCTAssertEqual(make(watched: [], turnedOff: turnedOff).rowPaths, [])
    }

    func testTheKeysStayOnTheRow() {
        var turnedOff = WatchedAppsTurnedOff()
        let watched = [editor, shell, studio]
        let before = make(watched: watched, turnedOff: turnedOff)
        var cursor = WatchedAppCursor(rows: before.rowPaths, selected: shell)
        let off = turnedOff.toggling(shell, in: watched, list: before)
        cursor.update(rows: make(watched: off, turnedOff: turnedOff).rowPaths)
        XCTAssertEqual(cursor.selected, shell)
        let on = turnedOff.toggling(cursor.selected!, in: off, list: make(watched: off, turnedOff: turnedOff))
        XCTAssertEqual(on, [editor, studio, shell])
        cursor.update(rows: make(watched: on, turnedOff: turnedOff).rowPaths)
        XCTAssertEqual(cursor.selected, shell)
    }
}

@MainActor
final class WatchedAppsPreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "WatchedAppsPreferenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testChoiceIsSavedAtOnceAndSentToTheHelper() {
        let preferences = SafetyPreferences(defaults: defaults)
        var changes = 0
        let subscription = preferences.changes.sink { changes += 1 }
        preferences.watchedAppPaths = WatchedAppSelection.setting("/Applications/Editor.app", isOn: true, in: preferences.watchedAppPaths)
        preferences.watchedAppPaths = WatchedAppSelection.setting("/Applications/Shell.app", isOn: true, in: preferences.watchedAppPaths)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(defaults.stringArray(forKey: "watchedAppPaths"), ["/Applications/Editor.app", "/Applications/Shell.app"])
        XCTAssertEqual(
            SafetyPreferences(defaults: defaults).watchedAppPaths,
            ["/Applications/Editor.app", "/Applications/Shell.app"]
        )
        preferences.watchedAppPaths = WatchedAppSelection.setting("/Applications/Editor.app", isOn: false, in: preferences.watchedAppPaths)
        XCTAssertEqual(SafetyPreferences(defaults: defaults).watchedAppPaths, ["/Applications/Shell.app"])
        subscription.cancel()
    }
}

final class WatchedAppActivityTests: XCTestCase {
    private let editor = "/Applications/Editor.app"

    /// The app's main process and one program it started, which has spent `seconds`.
    private func processes(started seconds: Double) -> [ProcessSnapshot] {
        [
            ProcessSnapshot(pid: 10, startTime: 1, parentPID: 1, path: editor + "/Contents/MacOS/Editor", cpuSeconds: 100),
            ProcessSnapshot(pid: 20, startTime: 2, parentPID: 10, path: "/usr/local/bin/agent", cpuSeconds: seconds),
        ]
    }

    func testNothingIsKnownFromOneReading() {
        var activity = WatchedAppActivity()
        XCTAssertNil(activity.add(processes(started: 0), at: 0, appPaths: [editor]))
    }

    func testAMinuteUsesTheHelpersThreshold() {
        var activity = WatchedAppActivity()
        _ = activity.add(processes(started: 0), at: 0, appPaths: [editor])
        XCTAssertEqual(activity.add(processes(started: 0.4), at: 60, appPaths: [editor]), [])
        var busy = WatchedAppActivity()
        _ = busy.add(processes(started: 0), at: 0, appPaths: [editor])
        XCTAssertEqual(busy.add(processes(started: 0.6), at: 60, appPaths: [editor]), [editor])
        XCTAssertEqual(WatchedApps.busyGroupSeconds, 0.5)
    }

    func testAShorterSpanShrinksTheThreshold() {
        var activity = WatchedAppActivity()
        _ = activity.add(processes(started: 0), at: 0, appPaths: [editor])
        // 0.5 s in a minute is 0.025 s in three seconds.
        XCTAssertEqual(activity.add(processes(started: 0.02), at: 3, appPaths: [editor]), [])
        XCTAssertEqual(activity.add(processes(started: 0.06), at: 6, appPaths: [editor]), [editor])
    }

    func testReadingsOlderThanAMinuteAreDropped() {
        var activity = WatchedAppActivity()
        _ = activity.add(processes(started: 0), at: 0, appPaths: [editor])
        _ = activity.add(processes(started: 5), at: 30, appPaths: [editor])
        // Compared with the reading at 30, not at 0.
        XCTAssertEqual(activity.add(processes(started: 5.1), at: 90, appPaths: [editor]), [])
    }
}
