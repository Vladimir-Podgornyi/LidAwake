import Foundation
import LidAwakeHelperKit
import LidAwakeShared

private let idleTimeout: TimeInterval = 120
private let limitCheckInterval: TimeInterval = 5
private let maximumLease = 600
private let runningBuild = HelperBuild.identifier(ofImage: #dsohandle)

// Accessed only on the main queue.
private let idleWatcher = IdleWatcher(
    source: SystemBusySignals(),
    clock: AwakeClock(),
    processes: SystemProcessTimes()
)

private let session = LidSession(
    flag: PmsetSleepFlag(),
    marker: FileOwnershipMarker(),
    clock: MonotonicClock(),
    awakeClock: AwakeClock(),
    power: IOKitPowerSource(),
    thermal: ProcessInfoThermalState(),
    idle: idleWatcher,
    stopReasons: FileStopReasonStore()
)

private let wakeScheduler = WakeScheduler(
    events: IOKitPowerEvents(),
    now: Date.init,
    calendar: {
        // The process caches the time zone; the system one may have changed since.
        NSTimeZone.resetSystemTimeZone()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }
)

final class Helper: NSObject, HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }

    func buildIdentifier(reply: @escaping (String?) -> Void) {
        reply(runningBuild)
    }

    func startSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        chargingOnly: Bool,
        idleSleepMinutes: Int,
        watchedAppPaths: [String],
        reply: @escaping (Int, String?) -> Void
    ) {
        let safety = SafetySettings(
            timerSeconds: timerSeconds,
            batteryLimitPercent: batteryLimitPercent,
            thermalProtection: thermalProtection,
            chargingOnly: chargingOnly,
            idleSleepMinutes: idleSleepMinutes,
            watchedAppPaths: watchedAppPaths
        )
        withLease(leaseSeconds, reply: reply) { session.start(lease: $0, safety: safety) }
    }

    func renewSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        chargingOnly: Bool,
        idleSleepMinutes: Int,
        watchedAppPaths: [String],
        reply: @escaping (Int, String?) -> Void
    ) {
        let safety = SafetySettings(
            timerSeconds: timerSeconds,
            batteryLimitPercent: batteryLimitPercent,
            thermalProtection: thermalProtection,
            chargingOnly: chargingOnly,
            idleSleepMinutes: idleSleepMinutes,
            watchedAppPaths: watchedAppPaths
        )
        withLease(leaseSeconds, reply: reply) { session.renew(lease: $0, safety: safety) }
    }

    func endSession(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.end() }
    }

    func clearLeftover(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.clearLeftover() }
    }

    func sessionStatus(reply: @escaping (Int, String?, Int, Int, Int, Int, Int, Int, Bool) -> Void) {
        DispatchQueue.main.async {
            let status = session.status()
            reply(
                HelperResultCode.ok.rawValue,
                status.message,
                status.flag.rawValue,
                status.session.rawValue,
                status.timerRemaining ?? -1,
                status.power.battery.wireValue,
                status.power.source.rawValue,
                status.thermal.rawValue,
                status.paused
            )
        }
    }

    func idleStatus(reply: @escaping (Int, String?, Int, Int, Int, Double, Double, String?, String?) -> Void) {
        DispatchQueue.main.async {
            let status = idleWatcher.status()
            reply(
                HelperResultCode.ok.rawValue,
                nil,
                status.state.rawValue,
                status.countedMinutes,
                status.requiredMinutes,
                status.cores ?? -1,
                status.inputIdleSeconds ?? -1,
                status.holders?.joined(separator: "\n"),
                WatchedAppState.encode(status.watched)
            )
        }
    }

    func lastStopReason(reply: @escaping (Int, String?, String?, Double, Int, Int) -> Void) {
        DispatchQueue.main.async {
            let record = session.lastStopReason()
            reply(
                HelperResultCode.ok.rawValue,
                nil,
                record?.reason.rawValue,
                record?.time.timeIntervalSince1970 ?? 0,
                record?.batteryPercent ?? -1,
                record?.idleMinutes ?? -1
            )
        }
    }

    func clearStopReason(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.clearStopReason() }
    }

    func takeIdleEvents(reply: @escaping (Int, String?, String?) -> Void) {
        DispatchQueue.main.async {
            reply(HelperResultCode.ok.rawValue, nil, IdleEventWire.encode(idleWatcher.takeEvents()))
        }
    }

    func setScheduledWake(minuteOfDay: Int, reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { wakeScheduler.set(minuteOfDay: minuteOfDay) }
    }

    func scheduledWakes(reply: @escaping (Int, String?, String?) -> Void) {
        DispatchQueue.main.async {
            do {
                reply(HelperResultCode.ok.rawValue, nil, ScheduledWakeWire.encode(try wakeScheduler.scheduledWakes()))
            } catch {
                reply(HelperResultCode.wakeScheduleFailed.rawValue, error.localizedDescription, nil)
            }
        }
    }

    private func withLease(
        _ seconds: Int,
        reply: @escaping (Int, String?) -> Void,
        _ action: @escaping (TimeInterval) -> SessionResult
    ) {
        guard (1...maximumLease).contains(seconds) else {
            reply(HelperResultCode.invalidArgument.rawValue, "Lease must be 1 to \(maximumLease) seconds.")
            return
        }
        perform(reply: reply) { action(TimeInterval(seconds)) }
    }

    private func perform(reply: @escaping (Int, String?) -> Void, _ action: @escaping () -> SessionResult) {
        DispatchQueue.main.async {
            let result = action()
            reply(result.code.rawValue, result.message)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private var connectionCount = 0
    private var idleExit: DispatchWorkItem?

    func scheduleIdleExit() {
        idleExit?.cancel()
        let item = DispatchWorkItem { [weak self] in
            // An active session needs the helper to enforce its lease and limits;
            // a leftover flag needs it to keep retrying the cleanup.
            if session.needsHelper {
                self?.scheduleIdleExit()
            } else {
                exit(0)
            }
        }
        idleExit = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: item)
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = Helper()
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connectionClosed() }
        }
        DispatchQueue.main.async { self.connectionOpened() }
        connection.resume()
        return true
    }

    private func connectionOpened() {
        connectionCount += 1
        idleExit?.cancel()
        idleExit = nil
    }

    private func connectionClosed() {
        connectionCount -= 1
        if connectionCount == 0 {
            scheduleIdleExit()
        }
    }
}

// The first reading right away, so the load can be averaged as soon as it is asked for.
idleWatcher.sample()
session.retryLeftover()

let limitTimer = DispatchSource.makeTimerSource(queue: .main)
limitTimer.schedule(deadline: .now() + limitCheckInterval, repeating: limitCheckInterval)
limitTimer.setEventHandler {
    session.enforceLimits()
    session.retryLeftover()
}
limitTimer.resume()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.setConnectionCodeSigningRequirement(HelperConstants.appRequirement)
listener.delegate = delegate
listener.resume()
delegate.scheduleIdleExit()
dispatchMain()
