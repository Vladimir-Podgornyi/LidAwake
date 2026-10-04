import Foundation
import IOKit.ps

public protocol PowerSourceMonitoring: AnyObject {
    /// Calls `handler` on the main thread each time the Mac switches between battery and AC power.
    func start(_ handler: @escaping () -> Void)
}

public final class IOKitPowerSourceMonitor: PowerSourceMonitoring {
    private var source: CFRunLoopSource?
    private var handler: (() -> Void)?
    private var providingType: String?

    public init() {}

    deinit {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    public func start(_ handler: @escaping () -> Void) {
        guard source == nil else { return }
        self.handler = handler
        providingType = Self.currentProvidingType()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().powerSourcesChanged()
        }, context)?.takeRetainedValue() else {
            return
        }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
    }

    // The notification also fires for every change in charge level.
    private func powerSourcesChanged() {
        let type = Self.currentProvidingType()
        guard type != providingType else { return }
        providingType = type
        handler?()
    }

    private static func currentProvidingType() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    }
}
