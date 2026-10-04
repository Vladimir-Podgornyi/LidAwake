import Foundation

@objc public protocol HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void)
}
