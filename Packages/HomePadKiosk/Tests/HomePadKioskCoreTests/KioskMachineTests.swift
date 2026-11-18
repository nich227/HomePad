import Foundation
import Testing
@testable import HomePadKioskCore

@Suite struct KioskMachineTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func on(passcodeSet: Bool = true, relock: Int = 30) -> KioskEvent {
        .configuration(enabled: true, passcodeSet: passcodeSet, relockSeconds: relock)
    }

    private let off = KioskEvent.configuration(enabled: false, passcodeSet: true, relockSeconds: 30)

    private func lockedMachine() -> KioskMachine {
        var machine = KioskMachine()
        _ = machine.handle(on(), now: start)
        _ = machine.handle(.engageFinished(success: true), now: start)
        return machine
    }

    private func releasedMachine(relock: Int = 30) -> KioskMachine {
        var machine = KioskMachine()
        _ = machine.handle(on(relock: relock), now: start)
        _ = machine.handle(.engageFinished(success: true), now: start)
        _ = machine.handle(.unlockTapped, now: start)
        _ = machine.handle(.passcode(.accepted), now: start)
        _ = machine.handle(.releaseFinished(success: true), now: start)
        return machine
    }

    @Test func configuration_whenEnabledWithPasscode_thenRequestsLock() {
        var machine = KioskMachine()
        #expect(machine.handle(on(), now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
        #expect(machine.handle(on(), now: start).isEmpty)
    }

    @Test func configuration_whenNoPasscode_thenUnavailableUntilOneIsSet() {
        var machine = KioskMachine()
        #expect(machine.handle(on(passcodeSet: false), now: start) == [.cancelRelock])
        #expect(machine.state == .unavailable(.noPasscode))
        #expect(machine.handle(on(), now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
    }

    @Test func configuration_whenDisabledAndNeverLocked_thenStaysOff() {
        var machine = KioskMachine()
        #expect(machine.handle(off, now: start) == [.cancelRelock])
        #expect(machine.state == .off)
        #expect(machine.handle(.sceneActivated, now: start).isEmpty)
        #expect(machine.handle(.guidedAccessChanged(active: true), now: start).isEmpty)
        #expect(machine.state == .off)
    }

    @Test func configuration_whenDisabledWhileLocked_thenReleases() {
        var machine = lockedMachine()
        #expect(machine.handle(off, now: start) == [.setSingleAppMode(false), .cancelRelock])
        #expect(machine.state == .off)
        #expect(machine.handle(.releaseFinished(success: true), now: start).isEmpty)
    }

    @Test func engageFinished_whenSucceeded_thenLocked_whenRefused_thenNotPermitted() {
        var machine = lockedMachine()
        #expect(machine.state == .locked(.singleAppMode))

        var refused = KioskMachine()
        _ = refused.handle(on(), now: start)
        #expect(refused.handle(.engageFinished(success: false), now: start).isEmpty)
        #expect(refused.state == .unavailable(.notPermitted))
        #expect(machine.handle(.engageFinished(success: false), now: start).isEmpty)
    }

    @Test func engageFinished_whenSettingTurnedOffMeanwhile_thenUndoesTheLock() {
        var machine = KioskMachine()
        _ = machine.handle(on(), now: start)
        #expect(machine.handle(off, now: start) == [.cancelRelock])
        #expect(machine.handle(.engageFinished(success: true), now: start) == [.setSingleAppMode(false)])
        #expect(machine.state == .off)
    }

    @Test func notPermitted_whenConfigurationRepeats_thenNoRetry_whenSceneActivates_thenRetries() {
        var machine = KioskMachine()
        _ = machine.handle(on(), now: start)
        _ = machine.handle(.engageFinished(success: false), now: start)
        #expect(machine.handle(on(), now: start).isEmpty)
        #expect(machine.state == .unavailable(.notPermitted))
        #expect(machine.handle(.sceneActivated, now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
    }

    @Test func unlockTapped_whenLocked_thenPromptsForPasscode_otherwiseIgnored() {
        var machine = lockedMachine()
        #expect(machine.handle(.unlockTapped, now: start) == [.promptForPasscode])
        #expect(machine.state == .authenticating)
        #expect(machine.handle(.unlockTapped, now: start).isEmpty)

        var idle = KioskMachine()
        #expect(idle.handle(.unlockTapped, now: start).isEmpty)
        #expect(idle.handle(.passcode(.accepted), now: start).isEmpty)
        #expect(idle.state == .off)
    }

    @Test func passcode_whenRejected_thenStaysLocked() {
        var machine = lockedMachine()
        _ = machine.handle(.unlockTapped, now: start)
        #expect(machine.handle(.passcode(.rejected), now: start).isEmpty)
        #expect(machine.state == .locked(.singleAppMode))
    }

    @Test(arguments: [PasscodeOutcome.accepted, .notSet])
    func passcode_whenAcceptedOrNoPasscodeExists_thenReleasesAndSchedulesRelock(outcome: PasscodeOutcome) {
        var machine = lockedMachine()
        _ = machine.handle(.unlockTapped, now: start)
        #expect(machine.handle(.passcode(outcome), now: start) == [.setSingleAppMode(false)])
        #expect(machine.state == .releasing)
        let deadline = start.addingTimeInterval(30)
        #expect(machine.handle(.releaseFinished(success: true), now: start) == [.scheduleRelock(at: deadline)])
        #expect(machine.state == .released(relockAt: deadline))
    }

    @Test func releaseFinished_whenSystemRefuses_thenStillLocked() {
        var machine = lockedMachine()
        _ = machine.handle(.unlockTapped, now: start)
        _ = machine.handle(.passcode(.accepted), now: start)
        #expect(machine.handle(.releaseFinished(success: false), now: start).isEmpty)
        #expect(machine.state == .locked(.singleAppMode))
    }

    @Test func relockInterval_whenSettingIsTiny_thenClampedToFiveSeconds() {
        let machine = releasedMachine(relock: 0)
        #expect(machine.state == .released(relockAt: start.addingTimeInterval(5)))
    }

    @Test func relockTimerFired_whenDeadlinePassed_thenLocksAgain_whenEarly_thenIgnored() {
        var machine = releasedMachine()
        #expect(machine.handle(.relockTimerFired, now: start.addingTimeInterval(29)).isEmpty)
        #expect(machine.handle(.relockTimerFired, now: start.addingTimeInterval(30)) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
        #expect(machine.handle(.relockTimerFired, now: start.addingTimeInterval(31)).isEmpty)
    }

    @Test func released_whenSceneActivatesWithoutLeaving_thenStaysReleased() {
        var machine = releasedMachine()
        #expect(machine.handle(.sceneActivated, now: start).isEmpty)
        #expect(machine.handle(on(), now: start).isEmpty)
        #expect(machine.state == .released(relockAt: start.addingTimeInterval(30)))
    }

    @Test func released_whenUserLeavesAndReturns_thenLocksAgain() {
        var machine = releasedMachine()
        #expect(machine.handle(.sceneBackgrounded, now: start) == [.cancelRelock])
        #expect(machine.handle(.sceneActivated, now: start.addingTimeInterval(600)) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
    }

    @Test func released_whenUserLeavesTurnsSettingOffAndReturns_thenOff() {
        var machine = releasedMachine()
        _ = machine.handle(.sceneBackgrounded, now: start)
        #expect(machine.handle(off, now: start) == [.cancelRelock])
        #expect(machine.handle(.sceneActivated, now: start).isEmpty)
        #expect(machine.state == .off)
    }

    @Test func sceneBackgrounded_whenNotReleased_thenIgnored() {
        var machine = lockedMachine()
        #expect(machine.handle(.sceneBackgrounded, now: start).isEmpty)
        #expect(machine.handle(.sceneActivated, now: start).isEmpty)
        #expect(machine.state == .locked(.singleAppMode))
    }

    @Test func guidedAccess_whenStartedByHandBeforeEnabling_thenCountsAsLocked() {
        var machine = KioskMachine()
        _ = machine.handle(.guidedAccessChanged(active: true), now: start)
        #expect(machine.handle(on(), now: start) == [.cancelRelock])
        #expect(machine.state == .locked(.guidedAccess))
        #expect(machine.handle(.unlockTapped, now: start).isEmpty)
    }

    @Test func guidedAccess_whenStartedByHandAfterRefusal_thenLocked_whenEnded_thenTriesAgain() {
        var machine = KioskMachine()
        _ = machine.handle(on(), now: start)
        _ = machine.handle(.engageFinished(success: false), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: true), now: start) == [.cancelRelock])
        #expect(machine.state == .locked(.guidedAccess))
        #expect(machine.handle(.guidedAccessChanged(active: false), now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)
    }

    @Test func guidedAccess_whenStatusEchoesOurOwnSession_thenIgnored() {
        var machine = KioskMachine()
        _ = machine.handle(on(), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: true), now: start).isEmpty)
        #expect(machine.state == .engaging)
        _ = machine.handle(.engageFinished(success: true), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: true), now: start).isEmpty)
        _ = machine.handle(.unlockTapped, now: start)
        _ = machine.handle(.passcode(.accepted), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: false), now: start).isEmpty)
        #expect(machine.state == .releasing)
        _ = machine.handle(.releaseFinished(success: true), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: false), now: start).isEmpty)
    }

    @Test func guidedAccess_whenOurSessionEndsFromOutside_thenLocksAgain() {
        var machine = lockedMachine()
        _ = machine.handle(.guidedAccessChanged(active: true), now: start)
        #expect(machine.handle(.guidedAccessChanged(active: false), now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(machine.state == .engaging)

        var prompting = lockedMachine()
        _ = prompting.handle(.unlockTapped, now: start)
        #expect(prompting.handle(.guidedAccessChanged(active: false), now: start) == [.cancelRelock, .setSingleAppMode(true)])
        #expect(prompting.handle(.passcode(.accepted), now: start).isEmpty)
    }

    @Test func guidedAccess_whenStartedByHandWhileReleased_thenLocked() {
        var machine = releasedMachine()
        #expect(machine.handle(.guidedAccessChanged(active: true), now: start) == [.cancelRelock])
        #expect(machine.state == .locked(.guidedAccess))
    }

    @Test func settings_describeBothRows() {
        #expect(KioskSettings.descriptors.map(\.name) == ["kiosk.enabled", "kiosk.relockSeconds"])
        #expect(KioskSettings.descriptors.allSatisfy { $0.pane == KioskSettings.pane })
        #expect(KioskSettings.enabled.defaultValue == false)
    }
}
