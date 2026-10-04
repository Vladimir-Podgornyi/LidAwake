import Combine
import Foundation

@MainActor
public protocol HelperInstalling: AnyObject {
    var state: HelperState { get }
    var isInApplications: Bool { get }
    func refresh() async
    func install() async
    func openSystemSettings()
}

extension HelperClient: HelperInstalling {}

/// Gets the helper ready when Run with Lid Closed is chosen and starts the mode once it is.
@MainActor
public final class HelperSetup: ObservableObject {
    /// What the window asks of the user; nil until Run with Lid Closed is chosen and while nothing is needed.
    @Published public private(set) var prompt: HelperPrompt?
    /// True while Run with Lid Closed waits for the helper and will start on its own.
    @Published public private(set) var isWaiting = false
    /// True while the helper is being checked or registered.
    @Published public private(set) var isWorking = false

    private let helper: HelperInstalling
    private let selectMode: (Mode) async throws -> Void
    private let pollSleep: () async throws -> Void
    private let approvalTimeout: TimeInterval
    private let now: () -> TimeInterval
    private var attempt = 0
    private var pollTask: Task<Void, Never>?

    public init(
        helper: HelperInstalling,
        selectMode: @escaping (Mode) async throws -> Void,
        pollSleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 2_000_000_000) },
        approvalTimeout: TimeInterval = 300,
        now: @escaping () -> TimeInterval = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
    ) {
        self.helper = helper
        self.selectMode = selectMode
        self.pollSleep = pollSleep
        self.approvalTimeout = approvalTimeout
        self.now = now
    }

    /// The choice of a mode card.
    public func select(_ mode: Mode) async {
        guard mode == .lidClosed else {
            cancel()
            try? await selectMode(mode)
            return
        }
        await requestLidClosed()
    }

    /// The action button of the current prompt.
    public func performPromptAction() async {
        switch prompt?.action {
        case .openSystemSettings:
            helper.openSystemSettings()
        case .tryAgain:
            await requestLidClosed()
        case nil:
            break
        }
    }

    private func requestLidClosed() async {
        guard !isWorking else { return }
        cancel()
        let current = attempt
        isWaiting = true
        isWorking = true
        defer { isWorking = false }

        await helper.refresh()
        guard current == attempt else { return }
        switch helper.state {
        case .ready, .requiresApproval:
            break
        case .notInstalled, .outdated, .error:
            guard helper.isInApplications else {
                stopWaiting(with: .moveToApplications)
                return
            }
            await helper.install()
            guard current == attempt else { return }
        }

        switch helper.state {
        case .ready:
            await start()
        case .requiresApproval:
            prompt = .approval
            waitForApproval(attempt: current)
        case .notInstalled:
            stopWaiting(with: .failed(String(localized: "The helper could not be installed.")))
        case .outdated:
            stopWaiting(with: .failed(String(localized: "The helper could not be updated.")))
        case .error(let message):
            stopWaiting(with: .failed(message))
        }
    }

    private func waitForApproval(attempt current: Int) {
        let deadline = now() + approvalTimeout
        pollTask = Task { [weak self] in
            while true {
                do {
                    try await self?.pollSleep()
                } catch {
                    return
                }
                guard let self, current == self.attempt else { return }
                await self.helper.refresh()
                guard current == self.attempt else { return }
                if self.helper.state == .ready {
                    await self.start()
                    return
                }
                if self.now() >= deadline {
                    // The approval prompt stays; only the automatic start is dropped.
                    self.isWaiting = false
                    return
                }
            }
        }
    }

    private func start() async {
        prompt = nil
        isWaiting = false
        pollTask = nil
        try? await selectMode(.lidClosed)
    }

    private func stopWaiting(with prompt: HelperPrompt) {
        self.prompt = prompt
        isWaiting = false
    }

    private func cancel() {
        attempt += 1
        pollTask?.cancel()
        pollTask = nil
        prompt = nil
        isWaiting = false
    }
}
