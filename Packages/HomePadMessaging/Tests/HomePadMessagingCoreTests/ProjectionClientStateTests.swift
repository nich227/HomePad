import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

@Suite struct ProjectionClientStateTests {
    private let calendarEntry = ProjectedAppEntryID(deviceID: Fixture.phoneID, appID: "calendar")

    private func announced(apps: [ProjectedApp] = [Fixture.app("calendar"), Fixture.app("nowPlaying", personal: false)]) throws -> ProjectionClientState {
        var state = ProjectionClientState(session: Fixture.hubSession)
        try state.apply(Fixture.hostFrame(.announce(apps), sequence: 1), from: Fixture.phone, now: Fixture.t0)
        return state
    }

    private func withRoot() throws -> ProjectionClientState {
        var state = try announced()
        try state.apply(Fixture.hostFrame(.setRoot(appID: "calendar", template: Fixture.list("root")), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        return state
    }

    // MARK: Announce and sessions

    @Test func apply_whenAnnounced_thenEntriesListTheAppsInOrder() throws {
        let state = try announced()
        let entries = state.entries(viewer: Fixture.aliceVerified)
        #expect(entries.map(\.id.appID) == ["calendar", "nowPlaying"])
        #expect(entries.allSatisfy { $0.deviceName == "Alice's iPhone" && $0.ownerProfileID == Fixture.alice && !$0.isRedacted })
        #expect(state.connectedDeviceIDs == [Fixture.phoneID])
    }

    @Test func apply_whenSenderIsNotACompanion_thenRejected() {
        var state = ProjectionClientState(session: Fixture.hubSession)
        #expect(throws: ProjectionStateError.senderRoleNotAllowed) {
            try state.apply(Fixture.hostFrame(.announce([Fixture.app()]), sequence: 1), from: Fixture.hub, now: Fixture.t0)
        }
        #expect(state.entries(viewer: Fixture.aliceVerified).isEmpty)
    }

    @Test func apply_whenFrameArrivesBeforeAnnounce_thenRejected() {
        var state = ProjectionClientState(session: Fixture.hubSession)
        #expect(throws: ProjectionStateError.notAnnounced) {
            try state.apply(Fixture.hostFrame(.setRoot(appID: "calendar", template: Fixture.list()), sequence: 1), from: Fixture.phone, now: Fixture.t0)
        }
    }

    @Test func apply_whenFrameIsFromAnotherSession_thenRejectedUntilThatSessionAnnounces() throws {
        var state = try withRoot()
        let newSession = UUID()
        #expect(throws: ProjectionStateError.notAnnounced) {
            try state.apply(Fixture.hostFrame(.pop(appID: "calendar"), sequence: 1, session: newSession), from: Fixture.phone, now: Fixture.t0)
        }
        try state.apply(Fixture.hostFrame(.announce([Fixture.app("calendar")]), sequence: 1, session: newSession), from: Fixture.phone, now: Fixture.t0)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .loading)
    }

    @Test func apply_whenSequenceDoesNotIncrease_thenRejected() throws {
        var state = try withRoot()
        for sequence: UInt64 in [1, 2] {
            #expect(throws: ProjectionStateError.staleSequence) {
                try state.apply(Fixture.hostFrame(.setRoot(appID: "calendar", template: Fixture.list("other")), sequence: sequence), from: Fixture.phone, now: Fixture.t0)
            }
        }
        #expect(throws: ProjectionStateError.staleSequence) {
            try state.apply(Fixture.hostFrame(.announce([]), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .template(Fixture.list("root"), receivedAt: Fixture.t0, depth: 1))
    }

    @Test func apply_whenRejectedFrameIsReplayed_thenSequenceWasAlreadyConsumed() throws {
        var state = try announced()
        let bad = Fixture.hostFrame(.setRoot(appID: "unknown", template: Fixture.list()), sequence: 2)
        #expect(throws: ProjectionStateError.unknownApp("unknown")) { try state.apply(bad, from: Fixture.phone, now: Fixture.t0) }
        #expect(throws: ProjectionStateError.staleSequence) { try state.apply(bad, from: Fixture.phone, now: Fixture.t0) }
    }

    @Test func apply_whenAnnouncedAgainInSameSession_thenKeepsStacksOfSurvivingApps() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "nowPlaying"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        try state.apply(Fixture.hostFrame(.announce([Fixture.app("calendar")]), sequence: 4), from: Fixture.phone, now: Fixture.t0)
        #expect(state.entries(viewer: Fixture.aliceVerified).map(\.id.appID) == ["calendar"])
        #expect(state.navigationDepth(for: calendarEntry) == 1)
        #expect(state.presentationRequest == nil)
    }

    @Test func apply_whenAnnouncedAppsAreInvalid_thenRejectedAndNothingChanges() throws {
        var state = try announced()
        #expect(throws: ProjectionStateError.invalid(.duplicateIdentifier(field: "app.id"))) {
            try state.apply(Fixture.hostFrame(.announce([Fixture.app("a"), Fixture.app("a")]), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(state.entries(viewer: Fixture.aliceVerified).count == 2)
    }

    // MARK: Navigation

    @Test func apply_whenSetRootPushPop_thenStackFollows() throws {
        var state = try withRoot()
        let later = Fixture.t0.addingTimeInterval(5)
        try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list("detail")), sequence: 3), from: Fixture.phone, now: later)
        #expect(state.navigationDepth(for: calendarEntry) == 2)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .template(Fixture.list("detail"), receivedAt: later, depth: 2))
        #expect(state.content(for: calendarEntry, depth: 1, viewer: Fixture.aliceVerified) == .template(Fixture.list("root"), receivedAt: Fixture.t0, depth: 1))
        try state.apply(Fixture.hostFrame(.pop(appID: "calendar"), sequence: 4), from: Fixture.phone, now: later)
        #expect(state.navigationDepth(for: calendarEntry) == 1)
        try state.apply(Fixture.hostFrame(.setRoot(appID: "calendar", template: Fixture.list("fresh")), sequence: 5), from: Fixture.phone, now: later)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .template(Fixture.list("fresh"), receivedAt: later, depth: 1))
    }

    @Test func apply_whenPushWithoutRoot_thenRejected() throws {
        var state = try announced()
        #expect(throws: ProjectionStateError.noRoot("calendar")) {
            try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list()), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        }
    }

    @Test func apply_whenPushExceedsDepthLimit_thenRejected() throws {
        var state = try withRoot()
        for depth in 2...5 {
            try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list("level\(depth)")), sequence: UInt64(depth + 1)), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.invalid(.navigationDepthExceeded(limit: 5))) {
            try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list("level6")), sequence: 10), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(state.navigationDepth(for: calendarEntry) == 5)
    }

    @Test func apply_whenPushRepeatsATemplateID_thenRejected() throws {
        var state = try withRoot()
        #expect(throws: ProjectionStateError.invalid(.duplicateIdentifier(field: "template.id"))) {
            try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list("root")), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        }
    }

    @Test func apply_whenPopAtRootOrWithoutRoot_thenRejected() throws {
        var state = try withRoot()
        #expect(throws: ProjectionStateError.cannotPopRoot("calendar")) {
            try state.apply(Fixture.hostFrame(.pop(appID: "calendar"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.cannotPopRoot("nowPlaying")) {
            try state.apply(Fixture.hostFrame(.pop(appID: "nowPlaying"), sequence: 4), from: Fixture.phone, now: Fixture.t0)
        }
    }

    @Test func apply_whenUpdateMatchesATemplateInTheStack_thenReplacesIt() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: Fixture.list("detail")), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        let updated = Fixture.list("root", title: "Updated")
        let later = Fixture.t0.addingTimeInterval(9)
        try state.apply(Fixture.hostFrame(.update(appID: "calendar", template: updated), sequence: 4), from: Fixture.phone, now: later)
        #expect(state.content(for: calendarEntry, depth: 1, viewer: Fixture.aliceVerified) == .template(updated, receivedAt: later, depth: 1))
        #expect(state.navigationDepth(for: calendarEntry) == 2)
    }

    @Test func apply_whenUpdateMatchesNothing_thenRejected() throws {
        var state = try withRoot()
        #expect(throws: ProjectionStateError.unknownTemplate("ghost")) {
            try state.apply(Fixture.hostFrame(.update(appID: "calendar", template: Fixture.list("ghost")), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.unknownTemplate("ghost")) {
            try state.apply(Fixture.hostFrame(.update(appID: "nowPlaying", template: Fixture.list("ghost")), sequence: 4), from: Fixture.phone, now: Fixture.t0)
        }
    }

    @Test func apply_whenTemplateIsInvalid_thenRejectedForEveryTemplateMessage() throws {
        var state = try withRoot()
        let bad = Fixture.list(title: "")
        let messages: [HostToHubMessage] = [.setRoot(appID: "calendar", template: bad), .push(appID: "calendar", template: bad), .update(appID: "calendar", template: bad)]
        for (offset, message) in messages.enumerated() {
            #expect(throws: ProjectionStateError.invalid(.emptyText(field: "template.title"))) {
                try state.apply(Fixture.hostFrame(message, sequence: UInt64(3 + offset)), from: Fixture.phone, now: Fixture.t0)
            }
        }
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .template(Fixture.list("root"), receivedAt: Fixture.t0, depth: 1))
    }

    @Test func apply_whenAppWasNotAnnounced_thenRejectedForEveryAppMessage() throws {
        var state = try announced()
        let messages: [HostToHubMessage] = [
            .setRoot(appID: "x", template: Fixture.list()), .push(appID: "x", template: Fixture.list()), .pop(appID: "x"),
            .update(appID: "x", template: Fixture.list()), .withdraw(appID: "x"), .present(appID: "x"),
        ]
        for (offset, message) in messages.enumerated() {
            #expect(throws: ProjectionStateError.unknownApp("x")) {
                try state.apply(Fixture.hostFrame(message, sequence: UInt64(2 + offset)), from: Fixture.phone, now: Fixture.t0)
            }
        }
    }

    @Test func apply_whenWithdrawn_thenAppAndItsContentAreGone() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "calendar"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        try state.apply(Fixture.hostFrame(.withdraw(appID: "calendar"), sequence: 4), from: Fixture.phone, now: Fixture.t0)
        #expect(state.entries(viewer: Fixture.aliceVerified).map(\.id.appID) == ["nowPlaying"])
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .unavailable)
        #expect(state.navigationDepth(for: calendarEntry) == 0)
        #expect(state.presentationRequest == nil)
    }

    @Test func apply_whenWithdrawnAppIsNotTheOnePresented_thenRequestStays() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "nowPlaying"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        try state.apply(Fixture.hostFrame(.withdraw(appID: "calendar"), sequence: 4), from: Fixture.phone, now: Fixture.t0)
        #expect(state.presentationRequest?.entryID.appID == "nowPlaying")
        try state.apply(Fixture.hostFrame(.announce([Fixture.app("nowPlaying", personal: false)]), sequence: 5), from: Fixture.phone, now: Fixture.t0)
        #expect(state.presentationRequest?.entryID.appID == "nowPlaying")
    }

    @Test func apply_whenPresentRequested_thenRequestIsRecordedAndCanBeCleared() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "calendar"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        #expect(state.presentationRequest == ProjectionPresentationRequest(entryID: calendarEntry, requestedAt: Fixture.t0))
        state.clearPresentationRequest()
        #expect(state.presentationRequest == nil)
    }

    // MARK: Visibility

    @Test func entries_whenDifferentMemberOrGuestIsPresent_thenPersonalAppIsNotListed() throws {
        let state = try withRoot()
        for viewer in [Fixture.bobVerified, ViewerContext.nobody] {
            #expect(state.entries(viewer: viewer).map(\.id.appID) == ["nowPlaying"])
            #expect(state.entry(calendarEntry, viewer: viewer) == nil)
            #expect(state.content(for: calendarEntry, viewer: viewer) == .unavailable)
        }
    }

    @Test func content_whenOwnerIsNotVerified_thenRedactedWithoutTheTemplate() throws {
        let state = try withRoot()
        #expect(state.entry(calendarEntry, viewer: Fixture.aliceManual)?.isRedacted == true)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceManual) == .redacted(.ownerNotVerified))
    }

    @Test func content_whenDepthIsOutsideTheStack_thenLoading() throws {
        let state = try withRoot()
        #expect(state.content(for: calendarEntry, depth: 3, viewer: Fixture.aliceVerified) == .loading)
        #expect(state.content(for: calendarEntry, depth: 0, viewer: Fixture.aliceVerified) == .loading)
    }

    @Test func content_whenDeviceIsUnknown_thenUnavailable() throws {
        let state = try withRoot()
        let unknown = ProjectedAppEntryID(deviceID: UUID(), appID: "calendar")
        #expect(state.content(for: unknown, viewer: Fixture.aliceVerified) == .unavailable)
        #expect(state.navigationDepth(for: unknown) == 0)
    }

    @Test func entries_whenTwoCompanionsProject_thenEachMemberSeesOnlyTheirOwnPersonalApps() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.announce([Fixture.app("calendar")]), sequence: 1, session: UUID()), from: Fixture.otherPhone, now: Fixture.t0)
        #expect(state.entries(viewer: Fixture.aliceVerified).map(\.id.deviceID) == [Fixture.phoneID, Fixture.phoneID])
        #expect(state.entries(viewer: Fixture.bobVerified).map(\.id) == [
            ProjectedAppEntryID(deviceID: Fixture.phoneID, appID: "nowPlaying"),
            ProjectedAppEntryID(deviceID: Fixture.otherPhoneID, appID: "calendar"),
        ])
    }

    // MARK: Connections

    @Test func deviceDisconnected_whenCompanionLeaves_thenItsAppsAndContentAreDropped() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "calendar"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        state.deviceDisconnected(Fixture.phoneID)
        #expect(state.entries(viewer: Fixture.aliceVerified).isEmpty)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .unavailable)
        #expect(state.presentationRequest == nil)
        #expect(state.connectedDeviceIDs.isEmpty)
    }

    @Test func deviceDisconnected_whenAnotherDeviceLeaves_thenPresentationRequestStays() throws {
        var state = try withRoot()
        try state.apply(Fixture.hostFrame(.present(appID: "calendar"), sequence: 3), from: Fixture.phone, now: Fixture.t0)
        state.deviceDisconnected(Fixture.otherPhoneID)
        #expect(state.presentationRequest != nil)
    }

    @Test func reconcile_whenCompanionIsNoLongerConnected_thenItsStateIsDropped() throws {
        var state = try withRoot()
        #expect(evaluated { state.reconcile(connected: [Fixture.hub], now: Fixture.t0) }.isEmpty)
        #expect(state.entries(viewer: Fixture.aliceVerified).isEmpty)
    }

    @Test func reconcile_whenCompanionHasNotAnnounced_thenGreetsOnceUntilRetryInterval() {
        var state = ProjectionClientState(session: Fixture.hubSession, helloRetryInterval: 10)
        #expect(evaluated { state.reconcile(connected: [Fixture.phone, Fixture.hub], now: Fixture.t0) } == [Fixture.phoneID])
        #expect(evaluated { state.reconcile(connected: [Fixture.phone], now: Fixture.t0.addingTimeInterval(9)) }.isEmpty)
        #expect(evaluated { state.reconcile(connected: [Fixture.phone], now: Fixture.t0.addingTimeInterval(10)) } == [Fixture.phoneID])
    }

    @Test func reconcile_whenGreetedCompanionLeavesAndReturns_thenGreetsAgain() {
        var state = ProjectionClientState(session: Fixture.hubSession)
        _ = state.reconcile(connected: [Fixture.phone], now: Fixture.t0)
        _ = state.reconcile(connected: [], now: Fixture.t0.addingTimeInterval(1))
        #expect(evaluated { state.reconcile(connected: [Fixture.phone], now: Fixture.t0.addingTimeInterval(2)) } == [Fixture.phoneID])
    }

    @Test func reconcile_whenAnnouncedCompanionChangesOwner_thenVisibilityFollowsTheNewOwner() throws {
        var state = try withRoot()
        var reassigned = Fixture.phone
        reassigned.profileID = Fixture.bob
        #expect(evaluated { state.reconcile(connected: [reassigned], now: Fixture.t0) }.isEmpty)
        #expect(state.content(for: calendarEntry, viewer: Fixture.aliceVerified) == .unavailable)
        #expect(state.entry(calendarEntry, viewer: Fixture.bobVerified) != nil)
    }

    // MARK: Outgoing

    @Test func frame_whenCalledRepeatedly_thenSequenceIncreasesFromOne() {
        var state = ProjectionClientState(session: Fixture.hubSession)
        let first = state.frame(for: .hello)
        let second = state.frame(for: .launch(appID: "calendar"))
        #expect(first == ProjectionFrame(session: Fixture.hubSession, sequence: 1, message: .hello))
        #expect(second.sequence == 2)
        #expect(state.limits == .standard)
    }
}
