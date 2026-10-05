import Combine
import Foundation

/// The blocks between the messages and the Quit row, top to bottom.
public enum WindowBlock: Hashable {
    /// Keep Screen On: the TIMER section with the timer row.
    case timer
    /// The row that collapses and expands the settings.
    case settingsToggle
    /// Off and Run with Lid Closed: the SAFETY section with four rows.
    case safety
    /// Keep Screen On: the dimmed SAFETY · LID CLOSED ONLY section.
    case dimmedSafety
    case settingsDivider
    case lockScreen
    case launchAtLogin
    case checkForUpdates
    case appearance
    case accent
    /// The divider above the Quit row.
    case closingDivider

    public static func list(mode: Mode, isExpanded: Bool, showsAppearance: Bool) -> [WindowBlock] {
        let layout = SafetyLayout(mode: mode)
        var blocks: [WindowBlock] = layout == .timerOnly ? [.timer, .settingsToggle] : [.settingsToggle]
        if isExpanded {
            switch layout {
            case .all: blocks += [.safety, .settingsDivider, .lockScreen]
            case .timerOnly: blocks += [.dimmedSafety, .settingsDivider]
            }
            blocks += [.launchAtLogin, .checkForUpdates]
            if showsAppearance {
                blocks.append(.appearance)
            }
            blocks.append(.accent)
        }
        blocks.append(.closingDivider)
        return blocks
    }
}

/// Kept apart from `SafetyPreferences`: whether the settings are expanded is never sent to the helper.
@MainActor
public final class SettingsDisclosurePreference: ObservableObject {
    public static let key = "settingsExpanded"

    @Published public var isExpanded: Bool {
        didSet { defaults.set(isExpanded, forKey: Self.key) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isExpanded = defaults.bool(forKey: Self.key)
    }
}
