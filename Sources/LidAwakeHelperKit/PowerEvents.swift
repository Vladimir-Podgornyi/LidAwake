import Foundation
import IOKit.pwr_mgt

/// Needs root to schedule and cancel.
public struct IOKitPowerEvents: PowerEventScheduling {
    public init() {}

    public func events() throws -> [PowerEvent] {
        // Nil when nothing is scheduled.
        guard let list = IOPMCopyScheduledPowerEvents()?.takeRetainedValue() else { return [] }
        guard let entries = list as? [[String: Any]] else { throw WakeScheduleError.unreadable }
        return entries.compactMap { entry in
            guard let time = entry[kIOPMPowerEventTimeKey] as? Date,
                  let owner = entry[kIOPMPowerEventAppNameKey] as? String,
                  let type = entry[kIOPMPowerEventTypeKey] as? String else { return nil }
            return PowerEvent(time: time, owner: owner, type: type)
        }
    }

    public func scheduleWake(at time: Date) throws {
        let result = IOPMSchedulePowerEvent(time as CFDate, WakeSchedule.owner as CFString, kIOPMAutoWake as CFString)
        guard result == kIOReturnSuccess else { throw WakeScheduleError.scheduleFailed(time, result) }
    }

    public func cancelWake(at time: Date) throws {
        let result = IOPMCancelScheduledPowerEvent(time as CFDate, WakeSchedule.owner as CFString, kIOPMAutoWake as CFString)
        guard result == kIOReturnSuccess else { throw WakeScheduleError.cancelFailed(time, result) }
    }
}
