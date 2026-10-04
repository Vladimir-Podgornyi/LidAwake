import Combine

public enum ModeError: Error, Equatable {
    case unavailable(Mode)
}

public final class ModeController: ObservableObject {
    @Published public private(set) var mode: Mode = .off

    private let displayAssertion: PowerAssertion

    public init(displayAssertion: PowerAssertion = DisplaySleepAssertion()) {
        self.displayAssertion = displayAssertion
    }

    public func select(_ newMode: Mode) throws {
        guard newMode != mode else { return }
        switch newMode {
        case .off:
            displayAssertion.release()
            mode = .off
        case .keepScreenOn:
            try displayAssertion.acquire()
            mode = .keepScreenOn
        case .lidClosed:
            throw ModeError.unavailable(.lidClosed)
        }
    }
}
