import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

@Suite struct ProjectionHostStateTests {
    private func registered() throws -> ProjectionHostState {
        var state = ProjectionHostState(session: Fixture.hostSession)
        _ = try state.register(Fixture.app("messages"), root: Fixture.list("root"))
        return state
    }

    // MARK: Apps and navigation

    @Test func register_whenValid_thenAnnouncesAndSetsRoot() throws {
        var state = ProjectionHostState(session: Fixture.hostSession)
        let messages = try state.register(Fixture.app("messages"), root: Fixture.list("root"))
        #expect(messages == [.announce([Fixture.app("messages")]), .setRoot(appID: "messages", template: Fixture.list("root"))])
        #expect(state.apps == [Fixture.app("messages")])
        #expect(state.stack(appID: "messages") == [Fixture.list("root")])
        #expect(state.limits == .standard)
    }

    @Test func register_whenSameAppRegisteredAgain_thenReplacesIt() throws {
        var state = try registered()
        var renamed = Fixture.app("messages")
        renamed.name = "Texts"
        _ = try state.register(renamed, root: Fixture.list("new"))
        #expect(state.apps == [renamed])
        #expect(state.stack(appID: "messages") == [Fixture.list("new")])
    }

    @Test func register_whenAppOrRootInvalid_thenRejectedAndNothingChanges() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.invalid(.invalidIdentifier(field: "app.id"))) { _ = try state.register(Fixture.app(""), root: Fixture.list()) }
        #expect(throws: ProjectionStateError.invalid(.emptyText(field: "template.title"))) { _ = try state.register(Fixture.app("b"), root: Fixture.list(title: "")) }
        #expect(state.apps.map(\.id) == ["messages"])
    }

    @Test func unregister_whenRegistered_thenWithdraws() throws {
        var state = try registered()
        #expect(try evaluated { try state.unregister(appID: "messages") } == [.withdraw(appID: "messages")])
        #expect(state.apps.isEmpty)
        #expect(state.stack(appID: "messages").isEmpty)
        #expect(throws: ProjectionStateError.unknownApp("messages")) { _ = try state.unregister(appID: "messages") }
    }

    @Test func navigation_whenPushPopSetRoot_thenStackAndMessagesFollow() throws {
        var state = try registered()
        #expect(try evaluated { try state.push(appID: "messages", template: Fixture.list("detail")) } == .push(appID: "messages", template: Fixture.list("detail")))
        #expect(state.stack(appID: "messages").map(\.id) == ["root", "detail"])
        #expect(try evaluated { try state.pop(appID: "messages") } == .pop(appID: "messages"))
        #expect(try evaluated { try state.setRoot(appID: "messages", template: Fixture.list("fresh")) } == .setRoot(appID: "messages", template: Fixture.list("fresh")))
        #expect(state.stack(appID: "messages").map(\.id) == ["fresh"])
    }

    @Test func navigation_whenAppUnknown_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.unknownApp("x")) { _ = try state.setRoot(appID: "x", template: Fixture.list()) }
        #expect(throws: ProjectionStateError.unknownApp("x")) { _ = try state.push(appID: "x", template: Fixture.list()) }
        #expect(throws: ProjectionStateError.unknownApp("x")) { _ = try state.pop(appID: "x") }
        #expect(throws: ProjectionStateError.unknownApp("x")) { _ = try state.update(appID: "x", template: Fixture.list()) }
    }

    @Test func navigation_whenTemplateInvalid_thenRejected() throws {
        var state = try registered()
        let bad = Fixture.list(title: "")
        #expect(throws: ProjectionStateError.invalid(.emptyText(field: "template.title"))) { _ = try state.setRoot(appID: "messages", template: bad) }
        #expect(throws: ProjectionStateError.invalid(.emptyText(field: "template.title"))) { _ = try state.push(appID: "messages", template: bad) }
        #expect(throws: ProjectionStateError.invalid(.emptyText(field: "template.title"))) {
            _ = try state.update(appID: "messages", template: Fixture.list("root", title: ""))
        }
    }

    @Test func push_whenDepthLimitReachedOrIDRepeats_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.invalid(.duplicateIdentifier(field: "template.id"))) {
            _ = try state.push(appID: "messages", template: Fixture.list("root"))
        }
        for depth in 2...5 {
            _ = try state.push(appID: "messages", template: Fixture.list("level\(depth)"))
        }
        #expect(throws: ProjectionStateError.invalid(.navigationDepthExceeded(limit: 5))) {
            _ = try state.push(appID: "messages", template: Fixture.list("level6"))
        }
    }

    @Test func pop_whenAtRoot_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.cannotPopRoot("messages")) { _ = try state.pop(appID: "messages") }
    }

    @Test func update_whenTemplateChanged_thenReplacesAndReturnsMessage() throws {
        var state = try registered()
        let updated = Fixture.list("root", title: "Updated")
        #expect(try evaluated { try state.update(appID: "messages", template: updated) } == .update(appID: "messages", template: updated))
        #expect(state.stack(appID: "messages") == [updated])
    }

    @Test func update_whenTemplateUnchanged_thenReturnsNil() throws {
        var state = try registered()
        #expect(try evaluated { try state.update(appID: "messages", template: Fixture.list("root")) } == nil)
    }

    @Test func update_whenTemplateNotInStack_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.unknownTemplate("ghost")) { _ = try state.update(appID: "messages", template: Fixture.list("ghost")) }
    }

    @Test func snapshot_whenAppsHaveStacks_thenAnnouncesThenRebuildsEachStackInOrder() throws {
        var state = try registered()
        _ = try state.push(appID: "messages", template: Fixture.list("detail"))
        _ = try state.register(Fixture.app("nowPlaying", personal: false), root: Fixture.allTemplates[2])
        #expect(state.snapshot() == [
            .announce(state.apps),
            .setRoot(appID: "messages", template: Fixture.list("root")),
            .push(appID: "messages", template: Fixture.list("detail")),
            .setRoot(appID: "nowPlaying", template: Fixture.allTemplates[2]),
        ])
    }

    @Test func snapshot_whenAppliedToAClient_thenClientMirrorsTheHost() throws {
        var host = try registered()
        _ = try host.push(appID: "messages", template: Fixture.list("detail"))
        var client = ProjectionClientState(session: Fixture.hubSession)
        for message in host.snapshot() {
            try client.apply(host.frame(for: message), from: Fixture.phone, now: Fixture.t0)
        }
        let entry = ProjectedAppEntryID(deviceID: Fixture.phoneID, appID: "messages")
        #expect(client.navigationDepth(for: entry) == 2)
        #expect(client.content(for: entry, viewer: Fixture.aliceVerified) == .template(Fixture.list("detail"), receivedAt: Fixture.t0, depth: 2))
    }

    @Test func frame_whenCalledRepeatedly_thenSequenceIncreasesFromOne() {
        var state = ProjectionHostState(session: Fixture.hostSession)
        #expect(evaluated { state.frame(for: .pop(appID: "a")) } == ProjectionFrame(session: Fixture.hostSession, sequence: 1, message: .pop(appID: "a")))
        #expect(evaluated { state.frame(for: .pop(appID: "a")) }.sequence == 2)
    }

    // MARK: Hubs

    @Test func reconcile_whenHubAppears_thenReportedOnceForASnapshot() {
        var state = ProjectionHostState(session: Fixture.hostSession)
        #expect(evaluated { state.reconcile(connected: [Fixture.hub, Fixture.otherPhone]) } == [Fixture.hubID])
        #expect(evaluated { state.reconcile(connected: [Fixture.hub]) }.isEmpty)
        #expect(state.hubIDs == [Fixture.hubID])
    }

    @Test func reconcile_whenHubLeavesAndReturns_thenReportedAgainAndItsSequenceIsForgotten() throws {
        var state = try registered()
        _ = state.reconcile(connected: [Fixture.hub])
        _ = try state.receive(Fixture.hubFrame(.hello, sequence: 5), from: Fixture.hub, now: Fixture.t0)
        #expect(state.lastHeard(from: Fixture.hubID) == Fixture.t0)
        #expect(evaluated { state.reconcile(connected: []) }.isEmpty)
        #expect(state.lastHeard(from: Fixture.hubID) == nil)
        #expect(evaluated { state.reconcile(connected: [Fixture.hub]) } == [Fixture.hubID])
        #expect(try evaluated { try state.receive(Fixture.hubFrame(.hello, sequence: 1), from: Fixture.hub, now: Fixture.t0) } == [.sendSnapshot(hubID: Fixture.hubID)])
    }

    @Test func receive_whenSenderIsNotAHub_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.senderRoleNotAllowed) {
            _ = try state.receive(Fixture.hubFrame(.hello, sequence: 1), from: Fixture.otherPhone, now: Fixture.t0)
        }
    }

    @Test func receive_whenHello_thenAsksForSnapshotOnce() throws {
        var state = try registered()
        #expect(try evaluated { try state.receive(Fixture.hubFrame(.hello, sequence: 1), from: Fixture.hub, now: Fixture.t0) } == [.sendSnapshot(hubID: Fixture.hubID)])
        #expect(state.hubIDs == [Fixture.hubID])
    }

    @Test func receive_whenFirstFrameOfASessionIsNotHello_thenSnapshotComesFirst() throws {
        var state = try registered()
        let events = try state.receive(Fixture.hubFrame(.launch(appID: "messages"), sequence: 4), from: Fixture.hub, now: Fixture.t0)
        #expect(events == [.sendSnapshot(hubID: Fixture.hubID), .launch(appID: "messages", hubID: Fixture.hubID)])
    }

    @Test func receive_whenHubRestartsWithNewSession_thenLowerSequenceIsAcceptedWithSnapshot() throws {
        var state = try registered()
        _ = try state.receive(Fixture.hubFrame(.hello, sequence: 50), from: Fixture.hub, now: Fixture.t0)
        let events = try state.receive(Fixture.hubFrame(.mediaCommand(.pause), sequence: 1, session: UUID()), from: Fixture.hub, now: Fixture.t0)
        #expect(events == [.sendSnapshot(hubID: Fixture.hubID), .mediaCommand(.pause, hubID: Fixture.hubID)])
    }

    @Test func receive_whenSequenceDoesNotIncrease_thenRejected() throws {
        var state = try registered()
        _ = try state.receive(Fixture.hubFrame(.hello, sequence: 3), from: Fixture.hub, now: Fixture.t0)
        for sequence: UInt64 in [3, 2] {
            #expect(throws: ProjectionStateError.staleSequence) {
                _ = try state.receive(Fixture.hubFrame(.reply(conversationID: "c", text: "Hi"), sequence: sequence), from: Fixture.hub, now: Fixture.t0)
            }
        }
    }

    @Test func receive_whenCommandsArrive_thenEventsCarryThem() throws {
        var state = try registered()
        _ = try state.receive(Fixture.hubFrame(.hello, sequence: 1), from: Fixture.hub, now: Fixture.t0)
        #expect(try evaluated { try state.receive(Fixture.hubFrame(.launch(appID: "messages"), sequence: 2), from: Fixture.hub, now: Fixture.t0) } == [.launch(appID: "messages", hubID: Fixture.hubID)])
        #expect(
            try evaluated { try state.receive(Fixture.hubFrame(.action(appID: "messages", actionID: "open.1", payload: ["k": "v"]), sequence: 3), from: Fixture.hub, now: Fixture.t0) }
                == [.action(appID: "messages", actionID: "open.1", payload: ["k": "v"], hubID: Fixture.hubID)]
        )
        #expect(
            try evaluated { try state.receive(Fixture.hubFrame(.action(appID: "messages", actionID: ProjectionReservedAction.back, payload: [:]), sequence: 4), from: Fixture.hub, now: Fixture.t0) }
                == [.back(appID: "messages", hubID: Fixture.hubID)]
        )
        #expect(
            try evaluated { try state.receive(Fixture.hubFrame(.reply(conversationID: "c1", text: "On my way"), sequence: 5), from: Fixture.hub, now: Fixture.t0) }
                == [.reply(conversationID: "c1", text: MemoryOnly("On my way"), hubID: Fixture.hubID)]
        )
        #expect(try evaluated { try state.receive(Fixture.hubFrame(.mediaCommand(.play), sequence: 6), from: Fixture.hub, now: Fixture.t0) } == [.mediaCommand(.play, hubID: Fixture.hubID)])
    }

    @Test func receive_whenAppUnknownOrContentInvalid_thenRejected() throws {
        var state = try registered()
        #expect(throws: ProjectionStateError.unknownApp("x")) {
            _ = try state.receive(Fixture.hubFrame(.launch(appID: "x"), sequence: 1), from: Fixture.hub, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.unknownApp("x")) {
            _ = try state.receive(Fixture.hubFrame(.action(appID: "x", actionID: "a", payload: [:]), sequence: 2), from: Fixture.hub, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.invalid(.invalidIdentifier(field: "actionID"))) {
            _ = try state.receive(Fixture.hubFrame(.action(appID: "messages", actionID: "", payload: [:]), sequence: 3), from: Fixture.hub, now: Fixture.t0)
        }
        #expect(throws: ProjectionStateError.invalid(.emptyText(field: "reply.text"))) {
            _ = try state.receive(Fixture.hubFrame(.reply(conversationID: "c", text: " "), sequence: 4), from: Fixture.hub, now: Fixture.t0)
        }
    }
}
