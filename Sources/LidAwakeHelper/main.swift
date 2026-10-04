import Foundation
import LidAwakeShared

private let idleTimeout: TimeInterval = 120

final class Helper: NSObject, HelperProtocol {
    func protocolVersion(reply: @escaping (Int) -> Void) {
        reply(HelperConstants.protocolVersion)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private var connectionCount = 0
    private var idleExit: DispatchWorkItem?

    func scheduleIdleExit() {
        idleExit?.cancel()
        let item = DispatchWorkItem { exit(0) }
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

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.setConnectionCodeSigningRequirement(HelperConstants.appRequirement)
listener.delegate = delegate
listener.resume()
delegate.scheduleIdleExit()
dispatchMain()
