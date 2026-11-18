import Foundation
import HomePadCore
import Synchronization
import Testing
@testable import HomePadFaceCore

/// Stands in for the system prompt. Hands out scripted results and can run a step while the
/// prompt is "showing".
private final class FakeAuthenticator: DeviceBiometricAuthenticating {
    private struct State {
        var results: [BiometricAttemptResult]
        var reasons: [String] = []
    }

    private let state: Mutex<State>
    private let kind: DeviceBiometryKind
    private let whilePrompting: (@Sendable () async -> Void)?

    init(
        _ results: [BiometricAttemptResult] = [.success],
        kind: DeviceBiometryKind = .touchID,
        whilePrompting: (@Sendable () async -> Void)? = nil
    ) {
        self.state = Mutex(State(results: results))
        self.kind = kind
        self.whilePrompting = whilePrompting
    }

    var reasons: [String] { state.withLock { $0.reasons } }

    func biometryKind() -> DeviceBiometryKind { kind }

    func authenticate(reason: String) async -> BiometricAttemptResult {
        state.withLock { $0.reasons.append(reason) }
        await whilePrompting?()
        return state.withLock { $0.results.isEmpty ? .success : $0.results.removeFirst() }
    }
}

@Suite struct DeviceBiometricUnlockPolicyTests {
    private func offered(setting: Bool = true, biometry: DeviceBiometryKind = .touchID, depth: Bool = false, waiting: Bool = true) -> Bool {
        DeviceBiometricUnlockPolicy.isOffered(settingEnabled: setting, biometry: biometry, hasDepthCamera: depth, cameraMatchWaiting: waiting)
    }

    @Test func isOffered_whenTouchIDWithoutDepthAndACameraMatchWaits_thenOffered() {
        #expect(offered())
    }

    @Test func isOffered_whenSettingIsOff_thenNotOffered() {
        #expect(!offered(setting: false))
    }

    @Test func isOffered_whenDeviceHasFaceIDOrNoBiometrics_thenNotOffered() {
        #expect(!offered(biometry: .faceID))
        #expect(!offered(biometry: .none))
    }

    @Test func isOffered_whenDepthCameraIsInUse_thenNotOffered() {
        #expect(!offered(depth: true))
    }

    @Test func isOffered_whenNoCameraMatchWaits_thenNotOffered() {
        #expect(!offered(waiting: false))
    }

    @Test func outcome_whenFingerAcceptedAndMatchStillWaits_thenConfirmed() {
        let outcome = DeviceBiometricUnlockPolicy.outcome(of: .success, cameraMatchStillWaiting: true)
        #expect(outcome == .confirmed)
        #expect(outcome.unlocksPersonalContent)
        #expect(!outcome.showsFailure)
        #expect(!outcome.mayRetry)
    }

    @Test func outcome_whenFingerAcceptedButMatchIsGone_thenNotAvailable() {
        let outcome = DeviceBiometricUnlockPolicy.outcome(of: .success, cameraMatchStillWaiting: false)
        #expect(outcome == .notAvailable)
        #expect(!outcome.unlocksPersonalContent)
        #expect(!outcome.showsFailure)
        #expect(!outcome.mayRetry)
    }

    @Test func outcome_whenAttemptDidNotSucceed_thenNothingUnlocksAndEachSaysWhatToDo() {
        let failed = DeviceBiometricUnlockPolicy.outcome(of: .failed, cameraMatchStillWaiting: true)
        #expect(failed == .failed)
        #expect(failed.showsFailure && failed.mayRetry && !failed.unlocksPersonalContent)
        let canceled = DeviceBiometricUnlockPolicy.outcome(of: .canceled, cameraMatchStillWaiting: true)
        #expect(canceled == .canceled)
        #expect(!canceled.showsFailure && canceled.mayRetry && !canceled.unlocksPersonalContent)
        let lockedOut = DeviceBiometricUnlockPolicy.outcome(of: .lockedOut, cameraMatchStillWaiting: true)
        #expect(lockedOut == .lockedOut)
        #expect(lockedOut.showsFailure && !lockedOut.mayRetry && !lockedOut.unlocksPersonalContent)
        #expect(DeviceBiometricUnlockPolicy.outcome(of: .notAvailable, cameraMatchStillWaiting: true) == .notAvailable)
    }

    @Test func result_whenMadeFromLocalAuthenticationErrorCode_thenMapsEachGroup() {
        #expect(BiometricAttemptResult(localAuthenticationErrorCode: -1) == .failed)
        for code in [-2, -3, -4, -9] {
            #expect(BiometricAttemptResult(localAuthenticationErrorCode: code) == .canceled)
        }
        #expect(BiometricAttemptResult(localAuthenticationErrorCode: -8) == .lockedOut)
        for code in [-5, -6, -7, -10, -1004, 0, 42] {
            #expect(BiometricAttemptResult(localAuthenticationErrorCode: code) == .notAvailable)
        }
    }
}

@MainActor
@Suite struct DeviceBiometricUnlockFlowTests {
    private let session: HouseholdSession
    private let alice: UUID
    private let bob: UUID
    private let date = Date(timeIntervalSince1970: 900)

    init() throws {
        session = HouseholdSession(store: InMemoryProfileStore())
        alice = try session.addProfile(name: "Alice").id
        bob = try session.addProfile(name: "Bob").id
    }

    private func unlock(
        _ flow: DeviceBiometricUnlockFlow,
        setting: Bool = true,
        biometry: DeviceBiometryKind = .touchID,
        depth: Bool = false
    ) async -> DeviceBiometricUnlockOutcome {
        await flow.unlock(settingEnabled: setting, biometry: biometry, hasDepthCamera: depth, reason: "Show personal content", at: date)
    }

    @Test func unlock_whenCameraMatchWaitsAndFingerIsAccepted_thenThatMembersPersonalContentUnlocks() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let authenticator = FakeAuthenticator()
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        #expect(flow.isOffered(settingEnabled: true, biometry: authenticator.biometryKind(), hasDepthCamera: false))
        #expect(await unlock(flow) == .confirmed)
        #expect(session.activation == .face(alice, at: date))
        #expect(session.isPersonalContentUnlocked)
        #expect(session.isConfirmedByDeviceBiometrics)
        #expect(authenticator.reasons == ["Show personal content"])
        #expect(!flow.isAuthenticating)
    }

    @Test func unlock_whenProfileWasPickedByHand_thenNotOfferedAndNoPromptIsShown() async throws {
        try session.switchManually(to: alice)
        let authenticator = FakeAuthenticator()
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        #expect(!flow.isOffered(settingEnabled: true, biometry: .touchID, hasDepthCamera: false))
        #expect(await unlock(flow) == .notAvailable)
        #expect(authenticator.reasons.isEmpty)
        #expect(session.activation == .manual(alice))
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func unlock_whenNobodyIsMatched_thenNotAvailableAndNoPromptIsShown() async {
        let authenticator = FakeAuthenticator()
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        #expect(await unlock(flow) == .notAvailable)
        #expect(authenticator.reasons.isEmpty)
        #expect(session.activation == .none)
    }

    @Test func unlock_whenNotOfferedOnThisDeviceOrBySetting_thenNotAvailableAndNoPromptIsShown() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let authenticator = FakeAuthenticator()
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        #expect(await unlock(flow, setting: false) == .notAvailable)
        #expect(await unlock(flow, biometry: .faceID) == .notAvailable)
        #expect(await unlock(flow, biometry: .none) == .notAvailable)
        #expect(await unlock(flow, depth: true) == .notAvailable)
        #expect(authenticator.reasons.isEmpty)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test(arguments: [
        (BiometricAttemptResult.failed, DeviceBiometricUnlockOutcome.failed),
        (.canceled, .canceled),
        (.lockedOut, .lockedOut),
        (.notAvailable, .notAvailable),
    ])
    func unlock_whenPromptDoesNotSucceed_thenContentStaysLockedAndTheMatchKeepsWaiting(
        result: BiometricAttemptResult,
        expected: DeviceBiometricUnlockOutcome
    ) async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: FakeAuthenticator([result]))
        #expect(await unlock(flow) == expected)
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.activation == .manual(alice))
        #expect(session.canConfirmWithDeviceBiometrics)
    }

    @Test func unlock_whenFingerFailsThenIsAccepted_thenSecondAttemptUnlocks() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: FakeAuthenticator([.failed, .success]))
        #expect(await unlock(flow) == .failed)
        #expect(await unlock(flow) == .confirmed)
        #expect(session.isPersonalContentUnlocked)
    }

    @Test func unlock_whenPersonLeavesWhileThePromptIsUp_thenAcceptedFingerUnlocksNothing() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let session = session
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: FakeAuthenticator(whilePrompting: {
            await MainActor.run { session.presenceLost() }
        }))
        #expect(await unlock(flow) == .notAvailable)
        #expect(session.activation == .none)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func unlock_whenAnotherMemberIsMatchedWhileThePromptIsUp_thenAcceptedFingerDoesNotUnlockThem() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let session = session
        let bob = bob
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: FakeAuthenticator(whilePrompting: {
            await MainActor.run {
                session.unknownFacePresent(proximity: .near)
                session.faceMatchedWithoutLiveness(profileID: bob, proximity: .near)
            }
        }))
        #expect(await unlock(flow) == .notAvailable)
        #expect(session.activation == .manual(bob))
        #expect(!session.isPersonalContentUnlocked)
        #expect(!session.isConfirmedByDeviceBiometrics)
    }

    @Test func unlock_whenSomeoneSwitchesByHandWhileThePromptIsUp_thenAcceptedFingerUnlocksNothing() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let session = session
        let bob = bob
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: FakeAuthenticator(whilePrompting: {
            await MainActor.run { try? session.switchManually(to: bob) }
        }))
        #expect(await unlock(flow) == .notAvailable)
        #expect(session.activation == .manual(bob))
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func unlock_whenAlreadyConfirmed_thenNotOfferedAgain() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let authenticator = FakeAuthenticator()
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        #expect(await unlock(flow) == .confirmed)
        #expect(await unlock(flow) == .notAvailable)
        #expect(authenticator.reasons.count == 1)
        #expect(session.isPersonalContentUnlocked)
    }

    @Test func unlock_whenAnAttemptIsAlreadyRunning_thenSecondAttemptShowsNoPrompt() async {
        session.faceMatchedWithoutLiveness(profileID: alice, proximity: .near)
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        let authenticator = FakeAuthenticator(whilePrompting: {
            for await _ in gate { break }
        })
        let flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        let first = Task { await unlock(flow) }
        while authenticator.reasons.isEmpty {
            await Task.yield()
        }
        #expect(flow.isAuthenticating)
        #expect(await unlock(flow) == .notAvailable)
        #expect(authenticator.reasons.count == 1)
        open.yield()
        #expect(await first.value == .confirmed)
        #expect(!flow.isAuthenticating)
    }
}
