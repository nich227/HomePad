import Foundation
import HomePadCore
import Testing
@testable import HomePadKioskCore

@MainActor
private final class FakeKioskSystem: KioskSystem {
    var isGuidedAccessActive = false
    var isPasscodeSet = true
    var permitsSingleAppMode = true
    var passcodeOutcome = PasscodeOutcome.accepted
    private(set) var requests: [Bool] = []
    private(set) var prompts = 0
    private var continuation: AsyncStream<Bool>.Continuation?

    func setSingleAppMode(_ enabled: Bool) async -> Bool {
        requests.append(enabled)
        return permitsSingleAppMode
    }

    func verifyPasscode() async -> PasscodeOutcome {
        prompts += 1
        return passcodeOutcome
    }

    func guidedAccessChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation = $0 }
    }

    func emitGuidedAccess(_ active: Bool) {
        isGuidedAccessActive = active
        continuation?.yield(active)
    }
}

@MainActor
private final class TestClock {
    var date = Date(timeIntervalSince1970: 1_000)
}

private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [TimeInterval] = []

    func wait(_ interval: TimeInterval) async {
        requested.append(interval)
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@MainActor
@Suite struct KioskLockControllerTests {
    private let system = FakeKioskSystem()
    private let gate = Gate()
    private let clock = TestClock()
    private let defaults: UserDefaults
    private let settings: HomePadSettings
    private let controller: KioskLockController

    init() {
        let suite = "KioskLockControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        self.defaults = defaults
        settings = HomePadSettings(defaults: defaults, notificationCenter: NotificationCenter())
        let gate = gate
        let clock = clock
        controller = KioskLockController(
            settings: settings,
            system: system,
            now: { clock.date },
            sleep: { await gate.wait($0) }
        )
    }

    private func enable() {
        defaults.set(true, forKey: KioskSettings.enabled.name)
        settings.refresh()
    }

    private func drain() async {
        for _ in 0..<20 { await Task.yield() }
        await controller.settle()
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func start_whenSettingOff_thenDoesNothing() async {
        controller.start()
        controller.start()
        await drain()
        #expect(controller.state == .off)
        #expect(!controller.isLocked)
        #expect(system.requests.isEmpty)
    }

    @Test func start_whenSettingOn_thenLocksAndUnlocksOnlyWithPasscode() async {
        enable()
        controller.start()
        #expect(controller.state == .engaging)
        #expect(!controller.isLocked)
        await drain()
        #expect(controller.state == .locked(.singleAppMode))
        #expect(controller.isLocked)

        system.passcodeOutcome = .rejected
        controller.requestUnlock()
        #expect(controller.state == .authenticating)
        #expect(controller.isLocked)
        await drain()
        #expect(controller.state == .locked(.singleAppMode))

        system.passcodeOutcome = .accepted
        controller.requestUnlock()
        await drain()
        #expect(controller.state == .released(relockAt: Date(timeIntervalSince1970: 1_030)))
        #expect(!controller.isLocked)
        #expect(system.requests == [true, false])
        #expect(system.prompts == 2)
        #expect(await gate.requested == [30])
    }

    @Test func relock_whenTimerFires_thenLocksAgain() async {
        enable()
        controller.start()
        await drain()
        controller.requestUnlock()
        await drain()
        clock.date = Date(timeIntervalSince1970: 1_030)
        await gate.open()
        await drain()
        #expect(controller.state == .locked(.singleAppMode))
        #expect(system.requests == [true, false, true])
    }

    @Test func relock_whenUserLeaves_thenTimerCancelledAndReturnLocks() async {
        enable()
        controller.start()
        await drain()
        controller.requestUnlock()
        await drain()
        controller.sceneEnteredBackground()
        await gate.open()
        await drain()
        #expect(system.requests == [true, false])
        controller.sceneBecameActive()
        await drain()
        #expect(controller.state == .locked(.singleAppMode))
    }

    @Test func settingsChange_whenToggledInSettings_thenFollows() async {
        controller.start()
        await drain()
        enable()
        await drain()
        #expect(controller.state == .locked(.singleAppMode))

        defaults.set(false, forKey: KioskSettings.enabled.name)
        settings.refresh()
        await drain()
        #expect(controller.state == .off)
        #expect(system.requests == [true, false])
    }

    @Test func notPermitted_whenDeviceRefuses_thenUnavailableAndGuidedAccessCovers() async {
        system.permitsSingleAppMode = false
        enable()
        controller.start()
        await drain()
        #expect(controller.state == .unavailable(.notPermitted))

        system.emitGuidedAccess(true)
        await drain()
        #expect(controller.state == .locked(.guidedAccess))
        #expect(controller.isLocked)
    }

    @Test func noPasscode_whenNoneSet_thenNeverLocks() async {
        system.isPasscodeSet = false
        enable()
        controller.start()
        await drain()
        #expect(controller.state == .unavailable(.noPasscode))
        #expect(system.requests.isEmpty)
    }

    @Test func defaults_whenClockAndSleepNotInjected_thenRelockUsesWallClock() async {
        enable()
        let live = KioskLockController(settings: settings, system: system)
        let before = Date()
        live.start()
        await live.settle()
        live.requestUnlock()
        await live.settle()
        for _ in 0..<20 { await Task.yield() }
        guard case .released(let deadline) = live.state else {
            Issue.record("expected released, got \(live.state)")
            return
        }
        #expect(deadline >= before.addingTimeInterval(30))
        live.stop()
    }

    @Test func stop_whenCalled_thenStopsFollowingSettingsAndSystem() async {
        controller.start()
        await drain()
        controller.stop()
        enable()
        system.emitGuidedAccess(true)
        await drain()
        #expect(controller.state == .off)
    }
}
