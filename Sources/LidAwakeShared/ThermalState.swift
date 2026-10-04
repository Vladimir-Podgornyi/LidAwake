import Foundation

public enum ThermalState: Int, Equatable {
    /// The system reported a value this build does not know.
    case unknown = -1
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    public var token: String {
        switch self {
        case .unknown: return "unknown"
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }
}

public protocol ThermalStateReading {
    func read() -> ThermalState
}

public struct ProcessInfoThermalState: ThermalStateReading {
    public init() {}

    public func read() -> ThermalState {
        ThermalState(ProcessInfo.processInfo.thermalState)
    }
}
