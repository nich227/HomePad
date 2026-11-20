import Foundation
import Testing
@testable import HomePadCore

@MainActor
@Suite struct HouseholdSessionTests {
    private func makeSession(limit: Int? = nil, requiresCompanion: Bool = false, store: any ProfileStore = InMemoryProfileStore()) -> HouseholdSession {
        HouseholdSession(store: store, profileLimit: limit, requiresCompanionForPersonalContent: requiresCompanion)
    }

    @Test func addProfile_whenNameValid_thenPersistsAndCyclesTints() throws {
        let store = InMemoryProfileStore()
        let session = makeSession(store: store)
        for index in 0..<7 {
            try session.addProfile(name: " Member \(index) ")
        }
        #expect(session.profiles.map(\.name).first == "Member 0")
        #expect(session.profiles.map(\.tint) == [.green, .yellow, .orange, .red, .purple, .blue, .green])
        #expect(try store.load() == session.profiles)
    }

    @Test func addProfile_whenNameBlank_thenThrowsEmptyName() {
        let session = makeSession()
        #expect(throws: HouseholdError.emptyName) { try session.addProfile(name: "  \n") }
    }

    @Test func addProfile_whenLimitReached_thenThrows() throws {
        let session = makeSession(limit: 1)
        try session.addProfile(name: "A", tint: .red, symbolName: "star")
        #expect(session.profiles[0].tint == .red)
        #expect(throws: HouseholdError.profileLimitReached(1)) { try session.addProfile(name: "B") }
    }

    @Test func init_whenStoreHasProfiles_thenLoadsThem() {
        let existing = HouseholdProfile(name: "A", tint: .blue)
        let session = makeSession(store: InMemoryProfileStore(profiles: [existing]))
        #expect(session.profiles == [existing])
    }

    @Test func init_whenStoreFails_thenStartsEmpty() {
        let session = makeSession(store: FailingStore())
        #expect(session.profiles.isEmpty)
    }

    @Test func updateProfile_whenKnown_thenReplaces() throws {
        let session = makeSession()
        var profile = try session.addProfile(name: "A")
        profile.name = "B"
        try session.updateProfile(profile)
        #expect(session.profiles.first?.name == "B")
    }

    @Test func updateProfile_whenUnknown_thenThrows() {
        let session = makeSession()
        let stranger = HouseholdProfile(name: "X", tint: .red)
        #expect(throws: HouseholdError.unknownProfile(stranger.id)) { try session.updateProfile(stranger) }
    }

    @Test func removeProfile_whenActive_thenLocksAndForgetsCompanion() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let other = try session.addProfile(name: "B")
        session.setCompanionPresent(true, for: profile.id)
        session.faceRecognized(profileID: profile.id, proximity: .near)
        try session.removeProfile(id: profile.id)
        #expect(session.activation == .none)
        #expect(session.profilesWithCompanionPresent.isEmpty)
        #expect(session.isGuest)

        try session.switchManually(to: other.id)
        let third = try session.addProfile(name: "C")
        try session.removeProfile(id: third.id)
        #expect(session.activation == .manual(other.id))
    }

    @Test func removeProfile_whenUnknown_thenThrows() {
        let session = makeSession()
        let id = UUID()
        #expect(throws: HouseholdError.unknownProfile(id)) { try session.removeProfile(id: id) }
    }

    @Test func faceRecognized_whenEnrolled_thenUnlocksPersonalContent() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let now = Date(timeIntervalSince1970: 100)
        session.faceRecognized(profileID: profile.id, proximity: .near, at: now)
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.activeProfile == profile)
        #expect(session.isPersonalContentUnlocked)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .near)
        #expect(!session.isGuest)
    }

    @Test func faceRecognized_whenNotEnrolled_thenIgnored() {
        let session = makeSession()
        session.faceRecognized(profileID: UUID(), proximity: .near)
        #expect(session.activation == .none)
        #expect(!session.isSomeonePresent)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func personalContent_whenCompanionRequired_thenNeedsCompanionPresent() throws {
        let session = makeSession(requiresCompanion: true)
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        #expect(!session.isPersonalContentUnlocked)
        session.setCompanionPresent(true, for: profile.id)
        #expect(session.isPersonalContentUnlocked)
        session.setCompanionPresent(false, for: profile.id)
        #expect(!session.isPersonalContentUnlocked)
        session.setCompanionPresent(true, for: UUID())
        #expect(session.profilesWithCompanionPresent.isEmpty)
    }

    @Test func switchManually_whenKnown_thenPersonalizesWithoutPersonalContent() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        try session.switchManually(to: profile.id)
        #expect(session.activeProfile == profile)
        #expect(!session.isPersonalContentUnlocked)
        session.lock()
        #expect(session.isGuest)
    }

    @Test func switchManually_whenUnknown_thenThrows() {
        let session = makeSession()
        let id = UUID()
        #expect(throws: HouseholdError.unknownProfile(id)) { try session.switchManually(to: id) }
    }

    @Test func unknownFacePresent_whenFaceActive_thenLocks_whenManual_thenKeeps() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        session.unknownFacePresent(proximity: .far)
        #expect(session.activation == .none)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .far)

        try session.switchManually(to: profile.id)
        session.unknownFacePresent(proximity: .near)
        #expect(session.activation == .manual(profile.id))
    }

    @Test func presenceLost_whenFaceActive_thenLocks_whenManual_thenKeeps() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        session.presenceLost()
        #expect(session.activation == .none)
        #expect(!session.isSomeonePresent)
        #expect(session.proximity == .far)

        try session.switchManually(to: profile.id)
        session.presenceLost()
        #expect(session.activation == .manual(profile.id))
    }

    @Test func faceMatchedWithoutLiveness_whenEnrolled_thenPersonalizesButStaysLocked() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .near)
        #expect(session.activation == .manual(profile.id))
        #expect(session.cameraMatchedProfileID == profile.id)
        #expect(session.canConfirmWithDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .near)

        session.faceMatchedWithoutLiveness(profileID: UUID(), proximity: .far)
        #expect(session.cameraMatchedProfileID == profile.id)
        #expect(session.proximity == .near)
    }

    @Test func confirmWithDeviceBiometrics_whenCameraMatchWaiting_thenUnlocksUntilPersonLeaves() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let now = Date(timeIntervalSince1970: 50)
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .near)
        #expect(session.confirmWithDeviceBiometrics(at: now))
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.isConfirmedByDeviceBiometrics)
        #expect(session.isPersonalContentUnlocked)
        #expect(!session.canConfirmWithDeviceBiometrics)

        // Later frames of the same unproven match must not lock it again.
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .far)
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.proximity == .far)

        session.presenceLost()
        #expect(session.activation == .none)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func confirmWithDeviceBiometrics_whenNoCameraMatch_thenRefused() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        #expect(!session.confirmWithDeviceBiometrics())

        try session.switchManually(to: profile.id)
        #expect(!session.confirmWithDeviceBiometrics())
        #expect(session.activation == .manual(profile.id))
        #expect(!session.isPersonalContentUnlocked)

        session.faceRecognized(profileID: profile.id, proximity: .near)
        #expect(!session.confirmWithDeviceBiometrics())
        #expect(!session.isConfirmedByDeviceBiometrics)
    }

    @Test func cameraMatch_whenAnotherMemberMatches_thenFirstMembersContentLocks() throws {
        let session = makeSession()
        let alice = try session.addProfile(name: "A")
        let bob = try session.addProfile(name: "B")
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.faceMatchedWithoutLiveness(profileID: bob.id, proximity: .near)
        #expect(session.activation == .manual(bob.id))
        #expect(session.cameraMatchedProfileID == bob.id)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func cameraMatch_whenUnknownFaceOrManualSwitchOrLock_thenCleared() throws {
        let session = makeSession()
        let alice = try session.addProfile(name: "A")
        let bob = try session.addProfile(name: "B")

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.unknownFacePresent(proximity: .near)
        #expect(session.activation == .none)
        #expect(session.cameraMatchedProfileID == nil)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        try session.switchManually(to: bob.id)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.confirmWithDeviceBiometrics())
        session.presenceLost()
        #expect(session.activation == .manual(bob.id))

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.lock()
        #expect(session.activation == .none)
        #expect(!session.isConfirmedByDeviceBiometrics)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.faceRecognized(profileID: alice.id, proximity: .near)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(session.isPersonalContentUnlocked)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        try session.removeProfile(id: alice.id)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(session.activation == .none)
    }

    @Test func activationProfileID_coversEveryCase() {
        let id = UUID()
        #expect(ProfileActivation.none.profileID == nil)
        #expect(ProfileActivation.manual(id).profileID == id)
        #expect(ProfileActivation.face(id, at: Date()).profileID == id)
    }
}

@MainActor
@Suite struct HouseholdSessionLingerTests {
    private let session: HouseholdSession
    private let alice: HouseholdProfile
    private let bob: HouseholdProfile
    private let start = Date(timeIntervalSince1970: 1_000)

    init() throws {
        session = HouseholdSession(store: InMemoryProfileStore(), lingerDuration: 120)
        alice = try session.addProfile(name: "Alice")
        bob = try session.addProfile(name: "Bob")
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Alice is recognized with a live face, then walks out of view at `start`.
    private func aliceStepsAway() -> Int {
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(-10))
        let generation = session.audienceGeneration
        session.presenceLost(at: start)
        return generation
    }

    // MARK: A member the camera recognized

    @Test func presenceLost_whenMemberWasRecognized_thenLingersWithPersonalContentLockedAtOnce() {
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(-10))
        #expect(session.isPersonalContentUnlocked)
        #expect(!session.isLingering)
        let generation = session.audienceGeneration

        session.presenceLost(at: start)
        #expect(session.activeProfile == alice)
        #expect(session.activation == .manual(alice.id))
        #expect(!session.isPersonalContentUnlocked)
        #expect(!session.canConfirmWithDeviceBiometrics)
        #expect(session.isLingering)
        #expect(session.lingerDeadline == at(120))
        #expect(!session.isSomeonePresent)
        #expect(session.proximity == .far)
        #expect(session.audienceGeneration == generation)
    }

    @Test func presenceLost_whenMemberWasConfirmedByDeviceBiometrics_thenLingersAndTheConfirmationIsGone() {
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near, at: at(-10))
        #expect(session.confirmWithDeviceBiometrics(at: at(-5)))
        let generation = session.audienceGeneration

        session.presenceLost(at: start)
        #expect(session.activation == .manual(alice.id))
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.canConfirmWithDeviceBiometrics)
        #expect(!session.confirmWithDeviceBiometrics(at: at(1)))
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.lingerDeadline == at(120))
        #expect(session.audienceGeneration == generation)
    }

    @Test func endLingerIfDue_whenDeadlinePasses_thenMemberSignsOut() {
        let generation = aliceStepsAway()
        #expect(!session.endLingerIfDue(at: at(119.9)))
        #expect(session.activeProfile == alice)
        #expect(session.audienceGeneration == generation)

        #expect(session.endLingerIfDue(at: at(120)))
        #expect(session.activation == .none)
        #expect(session.isGuest)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
        #expect(!session.endLingerIfDue(at: at(500)))
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func faceRecognized_whenSameMemberReturnsInTime_thenRestoredWithNothingLost() {
        let generation = aliceStepsAway()
        session.faceRecognized(profileID: alice.id, proximity: .mid, at: at(60))
        #expect(session.activation == .face(alice.id, at: at(60)))
        #expect(session.isPersonalContentUnlocked)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
        #expect(!session.endLingerIfDue(at: at(500)))
        #expect(session.activeProfile == alice)
    }

    @Test func faceMatchedWithoutLiveness_whenSameMemberReturnsInTime_thenRestoredAndCanConfirmAgain() {
        let generation = aliceStepsAway()
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near, at: at(60))
        #expect(session.activation == .manual(alice.id))
        #expect(session.canConfirmWithDeviceBiometrics)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
        #expect(!session.endLingerIfDue(at: at(500)))
    }

    @Test func faceRecognized_whenSameMemberReturnsAfterTheDeadline_thenTheyHadSignedOut() {
        let generation = aliceStepsAway()
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(121))
        #expect(session.activation == .face(alice.id, at: at(121)))
        #expect(session.audienceGeneration == generation + 2)
    }

    @Test func lock_whenLingering_thenSignsOutAtOnce() {
        let generation = aliceStepsAway()
        session.lock()
        #expect(session.activation == .none)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
        #expect(!session.endLingerIfDue(at: at(500)))
    }

    @Test func switchManually_whenLingeringAndAnotherProfileIsPicked_thenSignsOutAtOnce() throws {
        let generation = aliceStepsAway()
        try session.switchManually(to: bob.id)
        #expect(session.activation == .manual(bob.id))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
        #expect(!session.endLingerIfDue(at: at(500)))
        #expect(session.activation == .manual(bob.id))
    }

    @Test func switchManually_whenLingeringMemberIsPickedByHand_thenTheySimplyStay() throws {
        let generation = aliceStepsAway()
        try session.switchManually(to: alice.id)
        #expect(session.activation == .manual(alice.id))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
        #expect(!session.endLingerIfDue(at: at(500)))
        #expect(session.activeProfile == alice)
    }

    @Test func faceRecognized_whenLingeringAndAnotherMemberAppears_thenSignsOutAtOnce() {
        let generation = aliceStepsAway()
        session.faceRecognized(profileID: bob.id, proximity: .near, at: at(5))
        #expect(session.activation == .face(bob.id, at: at(5)))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func faceMatchedWithoutLiveness_whenLingeringAndAnotherMemberAppears_thenSignsOutAtOnce() {
        let generation = aliceStepsAway()
        session.faceMatchedWithoutLiveness(profileID: bob.id, proximity: .near, at: at(5))
        #expect(session.activation == .manual(bob.id))
        #expect(session.cameraMatchedProfileID == bob.id)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func unknownFacePresent_whenLingeringAndAJudgedFaceMatchesNobody_thenSignsOutAtOnce() {
        let generation = aliceStepsAway()
        session.unknownFacePresent(proximity: .near, at: at(5))
        #expect(session.activation == .none)
        #expect(session.isSomeonePresent)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func unknownFacePresent_whenRecognizedMemberIsReplaced_thenSignsOutAtOnce() {
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(-10))
        let generation = session.audienceGeneration
        session.unknownFacePresent(proximity: .near, at: start)
        #expect(session.activation == .none)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    // MARK: A face that cannot be judged

    @Test func faceUnreadable_whenMemberTurnsAway_thenStartsToLingerInsteadOfSigningOut() {
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(-10))
        let generation = session.audienceGeneration

        session.faceUnreadable(proximity: .mid, at: start)
        #expect(session.activeProfile == alice)
        #expect(session.activation == .manual(alice.id))
        #expect(!session.isPersonalContentUnlocked)
        #expect(!session.canConfirmWithDeviceBiometrics)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .mid)
        #expect(session.lingerDeadline == at(120))
        #expect(session.audienceGeneration == generation)
    }

    @Test func faceUnreadable_whenAlreadyLingering_thenTheDeadlineDoesNotMove() {
        let generation = aliceStepsAway()
        session.faceUnreadable(proximity: .near, at: at(30))
        #expect(session.lingerDeadline == at(120))
        #expect(session.isSomeonePresent)
        session.presenceLost(at: at(60))
        session.presenceLost(at: at(90))
        #expect(session.lingerDeadline == at(120))
        #expect(session.activeProfile == alice)
        #expect(session.audienceGeneration == generation)

        session.faceUnreadable(proximity: .near, at: at(120))
        #expect(session.isGuest)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func faceUnreadable_whenCameraMatchedMemberTurnsAway_thenLingers() {
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near, at: at(-10))
        session.faceUnreadable(proximity: .near, at: start)
        #expect(session.activation == .manual(alice.id))
        #expect(session.cameraMatchedProfileID == nil)
        #expect(session.lingerDeadline == at(120))
    }

    // MARK: A guest

    @Test func presenceLost_whenGuestWalksAway_thenLingersAndAnyFaceComingBackContinuesTheSession() {
        session.unknownFacePresent(proximity: .near, at: at(-10))
        let generation = session.audienceGeneration

        session.presenceLost(at: start)
        #expect(session.isGuest)
        #expect(session.lingerDeadline == at(120))
        #expect(session.audienceGeneration == generation)

        session.unknownFacePresent(proximity: .near, at: at(30))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)

        session.presenceLost(at: at(40))
        #expect(session.lingerDeadline == at(160))
        session.faceUnreadable(proximity: .near, at: at(50))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
        #expect(!session.endLingerIfDue(at: at(500)))
    }

    @Test func endLingerIfDue_whenGuestStaysAway_thenGuestSignsOut() {
        session.faceUnreadable(proximity: .near, at: at(-10))
        let generation = session.audienceGeneration
        session.presenceLost(at: start)
        #expect(session.endLingerIfDue(at: at(120)))
        #expect(session.isGuest)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func faceRecognized_whenGuestIsLingeringAndAMemberAppears_thenGuestSignsOut() {
        session.unknownFacePresent(proximity: .near, at: at(-10))
        let generation = session.audienceGeneration
        session.presenceLost(at: start)
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(5))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func presenceLost_whenTheCameraNeverSawAnyone_thenNothingStarts() {
        let generation = session.audienceGeneration
        session.presenceLost(at: start)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
    }

    // MARK: A member picked by hand

    @Test func presenceLost_whenHandPickedMemberWalksAway_thenLingersAndStaysPickedAfterSigningOut() throws {
        try session.switchManually(to: bob.id)
        session.unknownFacePresent(proximity: .near, at: at(-10))
        #expect(session.activation == .manual(bob.id))
        let generation = session.audienceGeneration

        session.presenceLost(at: start)
        #expect(session.activation == .manual(bob.id))
        #expect(session.lingerDeadline == at(120))
        #expect(session.audienceGeneration == generation)

        #expect(session.endLingerIfDue(at: at(120)))
        #expect(session.activation == .manual(bob.id))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    @Test func faceReturns_whenHandPickedMemberIsLingering_thenTheSessionContinues() throws {
        try session.switchManually(to: bob.id)
        session.faceUnreadable(proximity: .near, at: at(-10))
        let generation = session.audienceGeneration

        session.presenceLost(at: start)
        session.unknownFacePresent(proximity: .near, at: at(10))
        #expect(!session.isLingering)
        session.presenceLost(at: at(20))
        session.faceUnreadable(proximity: .near, at: at(30))
        #expect(!session.isLingering)
        session.presenceLost(at: at(40))
        session.faceRecognized(profileID: bob.id, proximity: .near, at: at(50))
        #expect(session.activation == .face(bob.id, at: at(50)))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
    }

    @Test func presenceLost_whenHandPickedAndTheCameraNeverSawAnyone_thenNothingStarts() throws {
        try session.switchManually(to: bob.id)
        let generation = session.audienceGeneration
        session.presenceLost(at: start)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation)
    }

    // MARK: Off

    @Test func lingerOff_whenTheCameraLosesTheAudience_thenTheySignOutAtOnce() throws {
        session.lingerDuration = 0
        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(-10))
        var generation = session.audienceGeneration
        session.presenceLost(at: start)
        #expect(session.activation == .none)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)

        session.faceRecognized(profileID: alice.id, proximity: .near, at: at(10))
        generation = session.audienceGeneration
        session.faceUnreadable(proximity: .near, at: at(20))
        #expect(session.activation == .none)
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)

        generation = session.audienceGeneration
        session.presenceLost(at: at(30))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
        session.presenceLost(at: at(31))
        #expect(session.audienceGeneration == generation + 1)

        try session.switchManually(to: bob.id)
        session.unknownFacePresent(proximity: .near, at: at(40))
        generation = session.audienceGeneration
        session.presenceLost(at: at(50))
        #expect(session.activation == .manual(bob.id))
        #expect(!session.isLingering)
        #expect(session.audienceGeneration == generation + 1)
    }

    // MARK: The one signal

    @Test func audienceGeneration_whenThePersonChanges_thenItChangesAndOtherwiseItDoesNot() throws {
        var generation = session.audienceGeneration
        session.faceRecognized(profileID: alice.id, proximity: .near, at: start)
        #expect(session.audienceGeneration == generation + 1)

        generation = session.audienceGeneration
        session.faceRecognized(profileID: alice.id, proximity: .far, at: at(1))
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near, at: at(2))
        session.confirmWithDeviceBiometrics(at: at(3))
        session.setCompanionPresent(true, for: alice.id)
        try session.switchManually(to: alice.id)
        #expect(session.audienceGeneration == generation)

        try session.switchManually(to: bob.id)
        #expect(session.audienceGeneration == generation + 1)
        try session.removeProfile(id: bob.id)
        #expect(session.audienceGeneration == generation + 2)
        session.lock()
        #expect(session.audienceGeneration == generation + 3)
        try session.removeProfile(id: alice.id)
        #expect(session.audienceGeneration == generation + 3)
    }

    @Test func dropDeviceBiometricConfirmation_whenConfirmed_thenLocksAgainWithoutSigningOut() {
        session.dropDeviceBiometricConfirmation()
        #expect(session.activation == .none)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near, at: start)
        session.dropDeviceBiometricConfirmation()
        #expect(session.canConfirmWithDeviceBiometrics)

        session.confirmWithDeviceBiometrics(at: at(1))
        let generation = session.audienceGeneration
        session.dropDeviceBiometricConfirmation()
        #expect(session.activation == .manual(alice.id))
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.canConfirmWithDeviceBiometrics)
        #expect(session.audienceGeneration == generation)
    }

    @Test func lingerDuration_whenNotGiven_thenOff() {
        #expect(HouseholdSession(store: InMemoryProfileStore()).lingerDuration == 0)
        #expect(session.lingerDuration == 120)
    }
}

private struct FailingStore: ProfileStore {
    struct Failure: Error {}
    func load() throws -> [HouseholdProfile] { throw Failure() }
    func save(_ profiles: [HouseholdProfile]) throws { throw Failure() }
}

@Suite struct ProfileStoreTests {
    @Test func fileStore_whenNoFile_thenEmpty_whenSaved_thenRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProfileStore(url: url)
        #expect(try store.load().isEmpty)
        let profiles = [HouseholdProfile(name: "A", tint: .purple, createdAt: Date(timeIntervalSince1970: 1_000))]
        try store.save(profiles)
        #expect(try store.load() == profiles)
    }

    @Test func applicationSupport_createsDirectory() throws {
        let store = try FileProfileStore.applicationSupport()
        _ = try store.load()
    }

    @Test func rainbowTint_hasSixDistinctColorsInRange() {
        let colors = RainbowTint.allCases.map(\.rgb)
        #expect(colors.count == 6)
        #expect(Set(colors.map { "\($0.red),\($0.green),\($0.blue)" }).count == 6)
        #expect(colors.allSatisfy { (0...1).contains($0.red) && (0...1).contains($0.green) && (0...1).contains($0.blue) })
    }
}

@Suite struct PeerChannelTests {
    private struct Ping: Codable, Equatable, Sendable { let value: Int }

    private func makePair() -> (LoopbackPeerChannel, LoopbackPeerChannel) {
        LoopbackPeerChannel.pair(
            PeerDevice(id: UUID(), name: "Hub", role: .hub),
            PeerDevice(id: UUID(), name: "Phone", role: .companion, profileID: UUID())
        )
    }

    @Test func send_whenPaired_thenDeliversOnlyOnThatChannel() async throws {
        let (hub, phone) = makePair()
        var beam = hub.messages(on: PeerChannelName.beam).makeAsyncIterator()
        var typed = hub.decoded(Ping.self, on: PeerChannelName.projection).makeAsyncIterator()

        try await phone.send(Data([1]), on: PeerChannelName.beam, to: hub.localDevice.id)
        try await phone.send(Data("not json".utf8), on: PeerChannelName.projection, to: nil)
        try await phone.send(Ping(value: 7), on: PeerChannelName.projection)

        let envelope = await beam.next()
        #expect(envelope == PeerEnvelope(channel: PeerChannelName.beam, sender: phone.localDevice.id, payload: Data([1])))
        let ping = await typed.next()
        #expect(ping?.message == Ping(value: 7))
        #expect(ping?.sender == phone.localDevice.id)
        #expect(await hub.connectedPeers() == [phone.localDevice])
    }

    @Test func send_whenPeerUnknown_thenThrows() async {
        let (hub, _) = makePair()
        let stranger = UUID()
        await #expect(throws: PeerChannelError.unknownPeer(stranger)) {
            try await hub.send(Data(), on: PeerChannelName.presence, to: stranger)
        }
    }

    @Test func send_whenDisconnected_thenThrowsAndPeersEmpty() async {
        let (hub, phone) = makePair()
        hub.disconnect()
        await #expect(throws: PeerChannelError.notConnected) {
            try await phone.send(Data(), on: PeerChannelName.intercom, to: nil)
        }
        #expect(await hub.connectedPeers().isEmpty)
        hub.disconnect()
    }

    @Test func messages_whenStreamCancelled_thenUnsubscribes() async throws {
        let (hub, phone) = makePair()
        let consumer = Task {
            for await _ in hub.decoded(Ping.self, on: PeerChannelName.beam) {}
        }
        consumer.cancel()
        await consumer.value
        try await phone.send(Ping(value: 1), on: PeerChannelName.beam)
        try await phone.send(Ping(value: 1), on: "nobody-listening")
    }
}
