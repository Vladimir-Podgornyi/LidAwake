public enum Mode: CaseIterable {
    case off
    case keepScreenOn
    case lidClosed

    /// The mode's name as its card shows it, for texts that name the chosen mode.
    public var name: String {
        switch self {
        case .off: return String(localized: "Off")
        case .keepScreenOn: return String(localized: "Keep Screen On")
        case .lidClosed: return String(localized: "Run with Lid Closed")
        }
    }
}
