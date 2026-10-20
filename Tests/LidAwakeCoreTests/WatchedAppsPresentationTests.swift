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
