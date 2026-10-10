import Foundation

@objc public protocol HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void)
    func startSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        chargingOnly: Bool,
        idleSleepMinutes: Int,
        reply: @escaping (Int, String?) -> Void
    )
    func renewSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        chargingOnly: Bool,
        idleSleepMinutes: Int,
        reply: @escaping (Int, String?) -> Void
    )
    func endSession(reply: @escaping (Int, String?) -> Void)
    func clearLeftover(reply: @escaping (Int, String?) -> Void)
    /// Replies with a result code, an error message, a `SleepFlagState`, a `SessionOwnership`,
    /// the seconds left on the timer (-1 when off), a `BatteryLevel` wire value, a `PowerSource`,
    /// a `ThermalState` and whether the session is paused.
    func sessionStatus(reply: @escaping (Int, String?, Int, Int, Int, Int, Int, Int, Bool) -> Void)
    /// Replies with a result code, an error message, an `IdleState` wire value, the counted and the
    /// required idle minutes, the cores busy over the last minute (-1 when unreadable), the seconds
    /// since the last input (-1 when unreadable) and the names of the processes whose sleep requests
    /// count, newline-separated (nil when the requests could not be read).
    func idleStatus(reply: @escaping (Int, String?, Int, Int, Int, Double, Double, String?) -> Void)
    /// Replies with a result code, an error message, a `StopReason` (nil when none),
    /// the time in seconds since 1970, the battery percentage (-1 when not recorded)
    /// and the idle minutes (-1 when not recorded).
    func lastStopReason(reply: @escaping (Int, String?, String?, Double, Int, Int) -> Void)
    func clearStopReason(reply: @escaping (Int, String?) -> Void)
}
