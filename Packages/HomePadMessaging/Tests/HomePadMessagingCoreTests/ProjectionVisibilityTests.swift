import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct ProjectionVisibilityTests {
    private func decide(owner: UUID?, personal: Bool, viewer: ViewerContext) -> VisibilityDecision {
        ProjectionVisibilityPolicy.decide(ownerProfileID: owner, requiresPersonalContent: personal, viewer: viewer)
    }

    @Test func decide_whenAppIsNotPersonal_thenVisibleToEveryone() {
        for viewer in [ViewerContext.nobody, Fixture.aliceVerified, Fixture.bobVerified] {
            #expect(decide(owner: Fixture.alice, personal: false, viewer: viewer) == VisibilityDecision(visibility: .visible, reason: .sharedContent))
        }
        #expect(decide(owner: nil, personal: false, viewer: .nobody).visibility == .visible)
    }

    @Test func decide_whenOwnerIsVerified_thenVisible() {
        #expect(decide(owner: Fixture.alice, personal: true, viewer: Fixture.aliceVerified) == VisibilityDecision(visibility: .visible, reason: .ownerVerified))
    }

    @Test func decide_whenOwnerSelectedByHand_thenRedacted() {
        #expect(decide(owner: Fixture.alice, personal: true, viewer: Fixture.aliceManual) == VisibilityDecision(visibility: .redacted, reason: .ownerNotVerified))
    }

    @Test func decide_whenDifferentMemberIsVerified_thenHidden() {
        #expect(decide(owner: Fixture.alice, personal: true, viewer: Fixture.bobVerified) == VisibilityDecision(visibility: .hidden, reason: .someoneElsePresent))
    }

    @Test func decide_whenGuestOrNobody_thenHidden() {
        #expect(decide(owner: Fixture.alice, personal: true, viewer: .nobody) == VisibilityDecision(visibility: .hidden, reason: .nobodyRecognized))
    }

    @Test func decide_whenUnlockedFlagIsSetWithoutAnActiveProfile_thenStillHidden() {
        let inconsistent = ViewerContext(activeProfileID: nil, isPersonalContentUnlocked: true)
        #expect(decide(owner: Fixture.alice, personal: true, viewer: inconsistent).visibility == .hidden)
    }

    @Test func decide_whenCompanionHasNoOwner_thenHiddenEvenWhenSomeoneIsVerified() {
        #expect(decide(owner: nil, personal: true, viewer: Fixture.aliceVerified) == VisibilityDecision(visibility: .hidden, reason: .noOwner))
    }
}
