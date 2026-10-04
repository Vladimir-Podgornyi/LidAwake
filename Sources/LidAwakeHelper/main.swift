import Foundation
import LidAwakeHelperKit
import LidAwakeShared

private let idleTimeout: TimeInterval = 120
private let limitCheckInterval: TimeInterval = 5
private let maximumLease = 600

// Accessed only on the main queue.
private let session = LidSession(
    flag: PmsetSleepFlag(),
    marker: FileOwnershipMarker(),
    clock: MonotonicClock(),
    power: IOKitPowerSource(),
    stopReasons: FileStopReasonStore()
)

final class Helper: NSObject, HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }

    func startSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        reply: @escaping (Int, String?) -> Void
    ) {
        let safety = SafetySettings(timerSeconds: timerSeconds, batteryLimitPercent: batteryLimitPercent)
        withLease(leaseSeconds, reply: reply) { session.start(lease: $0, safety: safety) }
    }

    func renewSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        reply: @escaping (Int, String?) -> Void
    ) {
        let safety = SafetySettings(timerSeconds: timerSeconds, batteryLimitPercent: batteryLimitPercent)
        withLease(leaseSeconds, reply: reply) { session.renew(lease: $0, safety: safety) }
    }

    func endSession(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.end() }
    }

    func clearLeftover(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.clearLeftover() }
    }

    func sessionStatus(reply: @escaping (Int, String?, Int, Int, Int, Int, Int) -> Void) {
        DispatchQueue.main.async {
            let status = session.status()
            reply(
                HelperResultCode.ok.rawValue,
                status.message,
                status.flag.rawValue,
                status.session.rawValue,
                status.timerRemaining ?? -1,
                status.power.battery.wireValue,
                status.power.source.rawValue
            )
        }
    }

    func lastStopReason(reply: @escaping (Int, String?, String?, Double, Int) -> Void) {
        DispatchQueue.main.async {
            let record = session.lastStopReason()
            reply(
                HelperResultCode.ok.rawValue,
                nil,
                record?.reason.rawValue,
                record?.time.timeIntervalSince1970 ?? 0,
                record?.batteryPercent ?? -1
            )
        }
    }

    func clearStopReason(reply: @escaping (Int, String?) -> Void) {
        perform(reply: reply) { session.clearStopReason() }
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
            // An active session needs the helper to enforce its lease and limits.
            if session.isActive {
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

let limitTimer = DispatchSource.makeTimerSource(queue: .main)
limitTimer.schedule(deadline: .now() + limitCheckInterval, repeating: limitCheckInterval)
limitTimer.setEventHandler { session.enforceLimits() }
limitTimer.resume()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.setConnectionCodeSigningRequirement(HelperConstants.appRequirement)
listener.delegate = delegate
listener.resume()
delegate.scheduleIdleExit()
dispatchMain()
