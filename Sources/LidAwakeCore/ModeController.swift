import Combine
import Foundation

@MainActor
public final class ModeController: ObservableObject {
    @Published public private(set) var mode: Mode = .off
    @Published public private(set) var lastError: String?
    @Published public private(set) var isBusy = false

    private let displayAssertion: PowerAssertion
    private let helper: HelperPreparing
    private let sessions: LidSessionService
    private let activity: ActivityHolding
    private let leaseSeconds: Int
    private let renewalSleep: () async throws -> Void
    private var renewalTask: Task<Void, Never>?

    public init(
        displayAssertion: PowerAssertion = DisplaySleepAssertion(),
        helper: HelperPreparing,
        sessions: LidSessionService,
        activity: ActivityHolding = AppNapActivity(),
        leaseSeconds: Int = 120,
        renewalSleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 30_000_000_000) }
    ) {
        self.displayAssertion = displayAssertion
        self.helper = helper
        self.sessions = sessions
        self.activity = activity
        self.leaseSeconds = leaseSeconds
        self.renewalSleep = renewalSleep
    }

    public func select(_ newMode: Mode) async throws {
        guard newMode != mode, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil

        do {
            switch newMode {
            case .off:
                await leaveCurrentMode()
                mode = .off
            case .keepScreenOn:
                await leaveCurrentMode()
                mode = .off
                try displayAssertion.acquire()
                mode = .keepScreenOn
            case .lidClosed:
                try await helper.prepareForSession()
                try await sessions.startSession(leaseSeconds: leaseSeconds)
                displayAssertion.release()
                activity.begin()
                mode = .lidClosed
                startRenewals()
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Clears a lid-closed flag left over from an earlier run, if the helper is ready.
    public func clearLeftover() async {
        guard await helper.isReady() else { return }
        do {
            try await sessions.clearLeftover()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func renew() async {
        guard mode == .lidClosed, !isBusy else { return }
        do {
            try await sessions.renewSession(leaseSeconds: leaseSeconds)
        } catch {
            // The user may have left the mode while the renewal was in flight.
            guard mode == .lidClosed, !isBusy else { return }
            isBusy = true
            defer { isBusy = false }
            await leaveCurrentMode()
            mode = .off
            lastError = error.localizedDescription
        }
    }

    private func leaveCurrentMode() async {
        switch mode {
        case .off:
            break
        case .keepScreenOn:
            displayAssertion.release()
        case .lidClosed:
            renewalTask?.cancel()
            renewalTask = nil
            do {
                try await sessions.endSession()
            } catch {
                lastError = error.localizedDescription
            }
            activity.end()
        }
    }

    private func startRenewals() {
        let sleep = renewalSleep
        renewalTask = Task { [weak self] in
            while true {
                do {
                    try await sleep()
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.renew()
            }
        }
    }
}
