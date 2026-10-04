import Foundation
import IOKit.ps

public enum BatteryLevel: Equatable {
    case percent(Int)
    case unknown
    /// The Mac has no internal battery.
    case none

    public init?(wireValue: Int) {
        switch wireValue {
        case -1: self = .unknown
        case -2: self = .none
        case 0...100: self = .percent(wireValue)
        default: return nil
        }
    }

    public var wireValue: Int {
        switch self {
        case .percent(let value): return value
        case .unknown: return -1
        case .none: return -2
        }
    }

    public var token: String {
        switch self {
        case .percent(let value): return String(value)
        case .unknown: return "unknown"
        case .none: return "none"
        }
    }
}

public enum PowerSource: Int, Equatable {
    case unknown = -1
    case ac = 0
    case battery = 1

    public var token: String {
        switch self {
        case .unknown: return "unknown"
        case .ac: return "ac"
        case .battery: return "battery"
        }
    }
}

public struct PowerReading: Equatable {
    public let battery: BatteryLevel
    public let source: PowerSource

    public init(battery: BatteryLevel, source: PowerSource) {
        self.battery = battery
        self.source = source
    }
}

public protocol PowerSourceReading {
    func read() -> PowerReading
}

public struct IOKitPowerSource: PowerSourceReading {
    public init() {}

    public func read() -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else {
            return PowerReading(battery: .unknown, source: .unknown)
        }
        let providing = Self.source(IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?)

        for item in list as NSArray as [AnyObject] {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }
            let state = Self.source(description[kIOPSPowerSourceStateKey] as? String)
            return PowerReading(battery: Self.level(description), source: state == .unknown ? providing : state)
        }
        return PowerReading(battery: .none, source: providing)
    }

    private static func level(_ description: [String: Any]) -> BatteryLevel {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0 else {
            return .unknown
        }
        let percent = (Double(current) * 100 / Double(maximum)).rounded()
        return .percent(min(100, max(0, Int(percent))))
    }

    private static func source(_ value: String?) -> PowerSource {
        switch value {
        case kIOPSACPowerValue: return .ac
        case kIOPSBatteryPowerValue: return .battery
        default: return .unknown
        }
    }
}
