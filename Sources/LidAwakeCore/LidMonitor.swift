import Foundation
import IOKit
import IOKit.pwr_mgt

public protocol LidMonitoring: AnyObject {
    /// Calls `handler` on the main thread each time the lid opens (false) or closes (true).
    func start(_ handler: @escaping (_ closed: Bool) -> Void)
}

/// Listens for general interest messages from IOPMrootDomain, which need no reply,
/// unlike the sleep messages delivered to IORegisterForSystemPower clients.
public final class IOKitLidMonitor: LidMonitoring {
    // kIOPMMessageClamshellStateChange from IOKit/pwr_mgt/IOPM.h:
    // iokit_family_msg(sub_iokit_powermanagement, 0x100). The macro is not imported into Swift.
    static let clamshellStateChange: UInt32 = 0xE003_4100
    static let clamshellStateBit = 1 << 0

    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var handler: ((Bool) -> Void)?
    private var closed = false

    public init() {}

    deinit {
        if notification != 0 {
            IOObjectRelease(notification)
        }
        if let port {
            IONotificationPortDestroy(port)
        }
    }

    public func start(_ handler: @escaping (Bool) -> Void) {
        guard port == nil else { return }
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return }
        defer { IOObjectRelease(rootDomain) }
        guard let created = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(created, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            created,
            rootDomain,
            kIOGeneralInterest,
            { context, _, messageType, argument in
                guard let context, messageType == IOKitLidMonitor.clamshellStateChange else { return }
                let bits = Int(bitPattern: argument)
                Unmanaged<IOKitLidMonitor>.fromOpaque(context).takeUnretainedValue()
                    .clamshellChanged(closed: bits & IOKitLidMonitor.clamshellStateBit != 0)
            },
            context,
            &notification
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(created)
            return
        }
        port = created
        self.handler = handler
        closed = Self.isClosed(rootDomain)
    }

    // The message also fires when only the "lid causes sleep" bit changes.
    private func clamshellChanged(closed newValue: Bool) {
        guard newValue != closed else { return }
        closed = newValue
        handler?(newValue)
    }

    private static func isClosed(_ rootDomain: io_service_t) -> Bool {
        let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }
}
