import Combine
import Foundation
import LidAwakeShared

@MainActor
public final class ModeController: ObservableObject {
    @Published public private(set) var mode: Mode = .off
    @Published public private(set) var lastError: String?
    @Published public private(set) var isBusy = false
    /// Monotonic time the current mode started; the timer counts from here.
    @Published public private(set) var modeStartedAt: TimeInterval?
    /// True while the helper holds Run with Lid Closed paused on battery power.
    @Published public private(set) var isPaused = false

    public let preferences: SafetyPreferences

    private let displayAssertion: PowerAssertion
    private let helper: HelperPreparing
    private let sessions: LidSessionService
    private let activity: ActivityHolding
    private let powerSourceMonitor: PowerSourceMonitoring
    private let notifier: StopNotifying
    private let lidMonitor: LidMonitoring
    private let screenLocker: ScreenLocking
    private let leaseSeconds: Int
    private let renewalSleep: () async throws -> Void
    private let timerCheckSleep: () async throws -> Void
    private let now: () -> TimeInterval
    private var renewalTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var preferenceChanges: AnyCancellable?
    private var requestedAuthorization = false

    public init(
        displayAssertion: PowerAssertion = DisplaySleepAssertion(),
        helper: HelperPreparing,
        sessions: LidSessionService,
        preferences: SafetyPreferences,
        notifier: StopNotifying,
        activity: ActivityHolding = AppNapActivity(),
        powerSourceMonitor: PowerSourceMonitoring = IOKitPowerSourceMonitor(),
        lidMonitor: LidMonitoring = IOKitLidMonitor(),
        screenLocker: ScreenLocking = LoginScreenLocker(),
        leaseSeconds: Int = 120,
        renewalSleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 30_000_000_000) },
        timerCheckSleep: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 5_000_000_000) },
        now: @escaping () -> TimeInterval = { TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
    ) {
        self.displayAssertion = displayAssertion
        self.helper = helper
        self.sessions = sessions
        self.preferences = preferences
        self.notifier = notifier
        self.activity = activity
        self.powerSourceMonitor = powerSourceMonitor
        self.lidMonitor = lidMonitor
        self.screenLocker = screenLocker
        self.leaseSeconds = leaseSeconds
        self.renewalSleep = renewalSleep
        self.timerCheckSleep = timerCheckSleep
        self.now = now
        preferenceChanges = preferences.changes.sink { [weak self] in
            Task { @MainActor in await self?.safetyChanged() }
        }
        powerSourceMonitor.start { [weak self] in
            Task { @MainActor in await self?.powerSourceChanged() }
        }
        lidMonitor.start { [weak self] closed in
            MainActor.assumeIsolated { self?.lidChanged(closed: closed) }
        }
    }

    /// Shown under the lock setting when it is on but this macOS cannot lock the screen.
    public var screenLockNotice: String? {
        preferences.lockOnLidCloseEnabled && !screenLocker.isAvailable ? ScreenLockNotice.unavailable : nil
    }

    /// Seconds left on the timer of the current mode; nil when the timer is off or no mode runs.
    public func timerRemaining() -> TimeInterval? {
        guard let modeStartedAt, let limit = preferences.timerLimit else { return nil }
        return max(0, TimeInterval(limit) - (now() - modeStartedAt))
    }

    public func select(_ newMode: Mode) async throws {
        guard newMode != mode, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        lastError = nil
        if newMode != .off {
            requestNotificationAuthorization()
        }

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
                startTimer()
            case .lidClosed:
                try await helper.prepareForSession()
                try await sessions.startSession(leaseSeconds: leaseSeconds, safety: preferences.helperSettings)
                displayAssertion.release()
                activity.begin()
                mode = .lidClosed
                startRenewals()
                startTimer()
                await updatePauseState()
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Clears a lid-closed flag left over from an earlier run and reports why the helper last stopped,
    /// if the helper is ready.
    public func clearLeftover() async {
        guard await helper.isReady() else { return }
        do {
            try await sessions.clearLeftover()
        } catch {
            lastError = error.localizedDescription
        }
        await reportStopReason()
    }

    func renew() async {
        guard mode == .lidClosed, !isBusy else { return }
        do {
            try await sessions.renewSession(leaseSeconds: leaseSeconds, safety: preferences.helperSettings)
            await updatePauseState()
        } catch {
            // The user may have left the mode while the renewal was in flight.
            guard mode == .lidClosed, !isBusy else { return }
            isBusy = true
            defer { isBusy = false }
            await leaveCurrentMode()
            mode = .off
            if case HelperError.helper(.noSession, _) = error, await reportStopReason() {
                return
            }
            lastError = error.localizedDescription
        }
    }

    func checkTimer() async {
        guard !isBusy, let remaining = timerRemaining(), remaining <= 0 else { return }
        switch mode {
        case .off:
            break
        case .keepScreenOn:
            isBusy = true
            defer { isBusy = false }
            await leaveCurrentMode()
            mode = .off
            report(StopRecord(reason: .timer, time: Date()))
        case .lidClosed:
            // The helper ends the session on its own; renewing finds out sooner.
            await renew()
        }
    }

    private func safetyChanged() async {
        switch mode {
        case .off:
            break
        case .keepScreenOn:
            await checkTimer()
        case .lidClosed:
            await renew()
        }
    }

    // Run with Lid Closed keeps the Mac awake, so the usual lock on sleep never happens.
    private func lidChanged(closed: Bool) {
        guard closed, mode == .lidClosed, preferences.lockOnLidCloseEnabled, screenLocker.isAvailable else { return }
        screenLocker.lock()
    }

    private func powerSourceChanged() async {
        guard mode == .lidClosed else { return }
        await renew()
    }

    /// Asks the helper whether the session is paused and announces a new pause.
    private func updatePauseState() async {
        guard let status = try? await sessions.sessionStatus(), mode == .lidClosed else { return }
        let wasPaused = isPaused
        isPaused = status.paused
        if isPaused && !wasPaused {
            notifier.post(title: PauseNotice.title, body: PauseNotice.body)
        }
    }

    private func requestNotificationAuthorization() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        notifier.requestAuthorization()
    }

    /// Shows and clears the reason the helper last ended a session; false when there is none.
    @discardableResult
    private func reportStopReason() async -> Bool {
        let record: StopRecord?
        do {
            record = try await sessions.lastStopReason()
        } catch {
            return false
        }
        guard let record else { return false }
        report(record)
        do {
            try await sessions.clearStopReason()
        } catch {
            lastError = error.localizedDescription
        }
        return true
    }

    // The window shows the text too, so it is seen even without notification permission.
    private func report(_ record: StopRecord) {
        let body = StopNotice.body(for: record)
        notifier.post(title: StopNotice.title, body: body)
        lastError = body
    }

    private func leaveCurrentMode() async {
        timerTask?.cancel()
        timerTask = nil
        modeStartedAt = nil
        switch mode {
        case .off:
            break
        case .keepScreenOn:
            displayAssertion.release()
        case .lidClosed:
            renewalTask?.cancel()
            renewalTask = nil
            isPaused = false
            do {
                try await sessions.endSession()
            } catch {
                lastError = error.localizedDescription
            }
            activity.end()
        }
    }

    private func startRenewals() {
        renewalTask = repeating(renewalSleep) { await $0.renew() }
    }

    private func startTimer() {
        modeStartedAt = now()
        timerTask?.cancel()
        timerTask = repeating(timerCheckSleep) { await $0.checkTimer() }
    }

    private func repeating(
        _ sleep: @escaping () async throws -> Void,
        _ action: @escaping (ModeController) async -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while true {
                do {
                    try await sleep()
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await action(self)
            }
        }
    }
}
