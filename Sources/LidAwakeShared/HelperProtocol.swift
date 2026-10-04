import Foundation

@objc public protocol HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void)
    func startSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        reply: @escaping (Int, String?) -> Void
    )
    func renewSession(
        leaseSeconds: Int,
        timerSeconds: Int,
        batteryLimitPercent: Int,
        thermalProtection: Bool,
        reply: @escaping (Int, String?) -> Void
    )
    func endSession(reply: @escaping (Int, String?) -> Void)
    func clearLeftover(reply: @escaping (Int, String?) -> Void)
    /// Replies with a result code, an error message, a `SleepFlagState`, a `SessionOwnership`,
    /// the seconds left on the timer (-1 when off), a `BatteryLevel` wire value, a `PowerSource`
    /// and a `ThermalState`.
    func sessionStatus(reply: @escaping (Int, String?, Int, Int, Int, Int, Int, Int) -> Void)
    /// Replies with a result code, an error message, a `StopReason` (nil when none),
    /// the time in seconds since 1970 and the battery percentage (-1 when not recorded).
    func lastStopReason(reply: @escaping (Int, String?, String?, Double, Int) -> Void)
    func clearStopReason(reply: @escaping (Int, String?) -> Void)
}
