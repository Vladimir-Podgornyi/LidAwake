import Foundation

@objc public protocol HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void)
    func startSession(leaseSeconds: Int, reply: @escaping (Int, String?) -> Void)
    func renewSession(leaseSeconds: Int, reply: @escaping (Int, String?) -> Void)
    func endSession(reply: @escaping (Int, String?) -> Void)
    func clearLeftover(reply: @escaping (Int, String?) -> Void)
    /// Replies with a result code, an error message, a `SleepFlagState` and a `SessionOwnership`.
    func sessionStatus(reply: @escaping (Int, String?, Int, Int) -> Void)
}
