import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

@Suite struct ReplyRoutingTests {
    private func context(
        owner: UUID? = Fixture.alice,
        companion: UUID? = Fixture.phoneID,
        viewer: ViewerContext = Fixture.aliceVerified,
        canReply: Bool = true,
        hubCanSend: Bool = false,
        hubOwner: UUID? = nil
    ) -> ReplyContext {
        ReplyContext(conversationOwner: owner, companionDeviceID: companion, viewer: viewer, canReply: canReply, hubCanSendText: hubCanSend, hubMessagesAccountOwner: hubOwner)
    }

    @Test func route_whenHubCannotSend_thenHandsOffToCompanion() {
        let route = ReplyRouting.route(context())
        #expect(route == .handOffToCompanion(deviceID: Fixture.phoneID))
        #expect(route.confirmationSite == .companion)
    }

    @Test func route_whenHubAccountBelongsToTheOwner_thenComposesOnHub() {
        let route = ReplyRouting.route(context(hubCanSend: true, hubOwner: Fixture.alice))
        #expect(route == .composeOnHub)
        #expect(route.confirmationSite == .hub)
    }

    @Test func route_whenHubAccountBelongsToSomeoneElse_thenNeverComposesOnHub() {
        #expect(ReplyRouting.route(context(hubCanSend: true, hubOwner: Fixture.bob)) == .handOffToCompanion(deviceID: Fixture.phoneID))
        #expect(ReplyRouting.route(context(hubCanSend: true, hubOwner: nil)) == .handOffToCompanion(deviceID: Fixture.phoneID))
        #expect(ReplyRouting.route(context(companion: nil, hubCanSend: true, hubOwner: Fixture.bob)) == .unavailable(.companionNotConnected))
    }

    @Test func route_whenHubAccountMatchesButHubCannotSend_thenHandsOff() {
        #expect(ReplyRouting.route(context(hubCanSend: false, hubOwner: Fixture.alice)) == .handOffToCompanion(deviceID: Fixture.phoneID))
    }

    @Test func route_whenHubComposesAndCompanionIsGone_thenStillComposesOnHub() {
        #expect(ReplyRouting.route(context(companion: nil, hubCanSend: true, hubOwner: Fixture.alice)) == .composeOnHub)
    }

    @Test func route_whenViewerIsNotTheVerifiedOwner_thenUnavailable() {
        for viewer in [Fixture.aliceManual, Fixture.bobVerified, ViewerContext.nobody] {
            let route = ReplyRouting.route(context(viewer: viewer, hubCanSend: true, hubOwner: Fixture.alice))
            #expect(route == .unavailable(.personalContentLocked))
            #expect(route.confirmationSite == nil)
        }
        #expect(ReplyRouting.route(context(owner: nil)) == .unavailable(.personalContentLocked))
    }

    @Test func route_whenConversationIsReadOnly_thenUnavailable() {
        #expect(ReplyRouting.route(context(canReply: false, hubCanSend: true, hubOwner: Fixture.alice)) == .unavailable(.conversationReadOnly))
    }

    @Test func route_whenNoCompanionAndHubCannotSend_thenUnavailable() {
        #expect(ReplyRouting.route(context(companion: nil)) == .unavailable(.companionNotConnected))
    }

    @Test func hubAccountOwner_whenNameMatchesOneProfile_thenResolvesIgnoringCaseAndAccents() {
        let profiles = [
            HouseholdProfile(id: Fixture.alice, name: "Alice", tint: .green),
            HouseholdProfile(id: Fixture.bob, name: "José", tint: .blue),
        ]
        #expect(ReplyRouting.hubAccountOwner(named: " alice ", in: profiles) == Fixture.alice)
        #expect(ReplyRouting.hubAccountOwner(named: "JOSE", in: profiles) == Fixture.bob)
    }

    @Test func hubAccountOwner_whenNameIsEmptyUnknownOrAmbiguous_thenNobody() {
        let profiles = [
            HouseholdProfile(id: Fixture.alice, name: "Sam", tint: .green),
            HouseholdProfile(id: Fixture.bob, name: "sam", tint: .blue),
        ]
        #expect(ReplyRouting.hubAccountOwner(named: "", in: profiles) == nil)
        #expect(ReplyRouting.hubAccountOwner(named: "   ", in: profiles) == nil)
        #expect(ReplyRouting.hubAccountOwner(named: "Carol", in: profiles) == nil)
        #expect(ReplyRouting.hubAccountOwner(named: "Sam", in: profiles) == nil)
    }
}
