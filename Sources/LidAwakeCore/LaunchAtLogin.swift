import Combine
import Foundation
import ServiceManagement

public enum LoginItemStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

public protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public struct MainAppLoginItemService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Remembers that the app has turned on launch at login by itself once.
public protocol LaunchAtLoginStore: AnyObject {
    var isInitialized: Bool { get set }
}

public final class DefaultsLaunchAtLoginStore: LaunchAtLoginStore {
    public static let key = "launchAtLoginInitialized"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isInitialized: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// The text under the Launch at login row.
public enum LaunchAtLoginNotice: Equatable {
    /// Registration failed or the system wants the user to allow it.
    case turnOnInSettings
    case moveToApplications

    public var text: String {
        switch self {
        case .turnOnInSettings:
            return String(localized: "Turn it on in System Settings > General > Login Items & Extensions.")
        case .moveToApplications:
            return String(localized: "Move LidAwake to the Applications folder to launch it at login.")
        }
    }
}

/// The Launch at login setting. Whether it is on is always read from the system,
/// since the user can turn the login item off in System Settings.
@MainActor
public final class LaunchAtLogin: ObservableObject {
    @Published public private(set) var isEnabled = false
    @Published public private(set) var notice: LaunchAtLoginNotice?

    private let service: LoginItemService
    private let store: LaunchAtLoginStore
    private let bundleURL: URL
    private var registrationFailed = false

    public init(
        service: LoginItemService = MainAppLoginItemService(),
        store: LaunchAtLoginStore = DefaultsLaunchAtLoginStore(),
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        self.service = service
        self.store = store
        self.bundleURL = bundleURL
        refresh()
    }

    public var isInApplications: Bool {
        bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path == "/Applications"
    }

    /// Launch at login is on by default: the first launch from /Applications registers the app.
    /// Once that has worked, only the user turns it on or off.
    public func enableOnFirstLaunch() {
        guard !store.isInitialized, isInApplications else {
            refresh()
            return
        }
        if service.status == .enabled || register() {
            store.isInitialized = true
        }
        refresh()
    }

    public func refresh() {
        let status = service.status
        isEnabled = status == .enabled
        if isEnabled {
            registrationFailed = false
        }
        if !isInApplications {
            notice = .moveToApplications
        } else if status == .requiresApproval || (registrationFailed && !isEnabled) {
            notice = .turnOnInSettings
        } else {
            notice = nil
        }
    }

    /// The toggle in the window.
    public func setEnabled(_ enabled: Bool) {
        guard isInApplications else {
            refresh()
            return
        }
        if enabled {
            if register() {
                store.isInitialized = true
            }
        } else {
            registrationFailed = false
            do {
                try service.unregister()
                store.isInitialized = true
            } catch {}
        }
        refresh()
    }

    private func register() -> Bool {
        do {
            try service.register()
            registrationFailed = false
            return true
        } catch {
            registrationFailed = true
            return false
        }
    }
}
