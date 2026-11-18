import Foundation
import HomePadCore
import Observation

/// The system calls the kiosk lock needs. The live implementation wraps UIKit and
/// LocalAuthentication; tests substitute a fake.
@MainActor
public protocol KioskSystem: AnyObject {
    var isGuidedAccessActive: Bool { get }
    var isPasscodeSet: Bool { get }
    /// Asks the system to lock the device to this app, or to release it. Returns whether it did.
    func setSingleAppMode(_ enabled: Bool) async -> Bool
    /// Shows the device passcode prompt. Biometrics must not satisfy it.
    func verifyPasscode() async -> PasscodeOutcome
    func guidedAccessChanges() -> AsyncStream<Bool>
}

/// Runs the kiosk lock: follows the Settings toggle, locks the iPad to the app, and releases the
/// lock only after the iPad passcode is entered.
@MainActor
@Observable
public final class KioskLockController {
    public private(set) var state: KioskState = .off

    @ObservationIgnored private var machine = KioskMachine()
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let system: any KioskSystem
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var relock: Task<Void, Never>?
    @ObservationIgnored private var work: [Task<Void, Never>] = []

    public init(
        settings: HomePadSettings,
        system: any KioskSystem,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.settings = settings
        self.system = system
        self.now = now
        self.sleep = sleep
    }

    public var isLocked: Bool {
        switch state {
        case .locked, .authenticating, .releasing: true
        case .off, .engaging, .released, .unavailable: false
        }
    }

    public func start() {
        guard watcher == nil else { return }
        send(.guidedAccessChanged(active: system.isGuidedAccessActive))
        let changes = system.guidedAccessChanges()
        watcher = Task { [weak self] in
            for await active in changes {
                self?.send(.guidedAccessChanged(active: active))
            }
        }
        applyConfiguration()
        observeSettings()
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        relock?.cancel()
        relock = nil
    }

    public func sceneBecameActive() {
        applyConfiguration()
        send(.sceneActivated)
    }

    public func sceneEnteredBackground() {
        send(.sceneBackgrounded)
    }

    public func requestUnlock() {
        send(.unlockTapped)
    }

    /// Waits for every lock request and passcode prompt started so far.
    func settle() async {
        while let task = work.first {
            await task.value
            work.removeFirst()
        }
    }

    private func applyConfiguration() {
        send(.configuration(
            enabled: settings[KioskSettings.enabled],
            passcodeSet: system.isPasscodeSet,
            relockSeconds: settings[KioskSettings.relockSeconds]
        ))
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings[KioskSettings.enabled]
            _ = settings[KioskSettings.relockSeconds]
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.watcher != nil else { return }
                self.applyConfiguration()
                self.observeSettings()
            }
        }
    }

    private func send(_ event: KioskEvent) {
        let effects = machine.handle(event, now: now())
        state = machine.state
        for effect in effects {
            perform(effect)
        }
    }

    private func perform(_ effect: KioskEffect) {
        switch effect {
        case .setSingleAppMode(let enabled):
            work.append(Task { [weak self, system] in
                let succeeded = await system.setSingleAppMode(enabled)
                self?.send(enabled ? .engageFinished(success: succeeded) : .releaseFinished(success: succeeded))
            })
        case .promptForPasscode:
            work.append(Task { [weak self, system] in
                let outcome = await system.verifyPasscode()
                self?.send(.passcode(outcome))
            })
        case .scheduleRelock(let deadline):
            relock?.cancel()
            let delay = max(deadline.timeIntervalSince(now()), 0)
            relock = Task { [weak self, sleep] in
                await sleep(delay)
                guard !Task.isCancelled else { return }
                self?.send(.relockTimerFired)
            }
        case .cancelRelock:
            relock?.cancel()
            relock = nil
        }
    }
}
