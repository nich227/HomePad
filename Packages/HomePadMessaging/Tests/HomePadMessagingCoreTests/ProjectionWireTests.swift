import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct ProjectionWireTests {
    let codec = ProjectionCodec()

    private static let hostMessages: [HostToHubMessage] = [
        .announce([Fixture.app("messages"), Fixture.app("nowPlaying", personal: false)]),
        .setRoot(appID: "messages", template: Fixture.allTemplates[3]),
        .push(appID: "messages", template: Fixture.allTemplates[4]),
        .pop(appID: "messages"),
        .update(appID: "messages", template: Fixture.allTemplates[2]),
        .withdraw(appID: "messages"),
        .present(appID: "messages"),
    ]

    private static let hubMessages: [HubToHostMessage] = [
        .hello,
        .launch(appID: "messages"),
        .action(appID: "messages", actionID: "messages.open.c1", payload: ["value": "true"]),
        .action(appID: "messages", actionID: ProjectionReservedAction.back, payload: [:]),
        .reply(conversationID: "c1", text: "On my way"),
        .mediaCommand(.nextTrack),
    ]

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test(arguments: hostMessages)
    func hostFrame_whenEncodedAndDecoded_thenRoundTrips(message: HostToHubMessage) throws {
        let frame = Fixture.hostFrame(message, sequence: 7)
        #expect(try codec.decodeHostFrame(codec.encode(frame)) == frame)
    }

    @Test(arguments: hubMessages)
    func hubFrame_whenEncodedAndDecoded_thenRoundTrips(message: HubToHostMessage) throws {
        let frame = Fixture.hubFrame(message, sequence: 9)
        #expect(try codec.decodeHubFrame(codec.encode(frame)) == frame)
    }

    @Test(arguments: Fixture.allTemplates)
    func template_whenSentAsRoot_thenRoundTrips(template: ProjectionTemplate) throws {
        let frame = Fixture.hostFrame(.setRoot(appID: "app", template: template), sequence: 1)
        #expect(try codec.decodeHostFrame(codec.encode(frame)) == frame)
    }

    @Test func decode_whenVersionIsNewer_thenFailsClosedBeforeReadingTheBody() throws {
        let data = try json(["version": 2, "type": "announce", "somethingNew": true])
        #expect(throws: ProjectionWireError.unsupportedVersion(2)) { try codec.decodeHostFrame(data) }
        #expect(throws: ProjectionWireError.unsupportedVersion(2)) { try codec.decodeHubFrame(data) }
    }

    @Test func decode_whenVersionIsZero_thenFails() throws {
        var frame = try object(codec.encode(Fixture.hubFrame(.hello, sequence: 1)))
        frame["version"] = 0
        #expect(throws: ProjectionWireError.unsupportedVersion(0)) { try codec.decodeHubFrame(json(frame)) }
    }

    @Test func decode_whenMessageTypeIsUnknown_thenFailsClosed() throws {
        var frame = try object(codec.encode(Fixture.hostFrame(.pop(appID: "a"), sequence: 1)))
        frame["type"] = "teleport"
        #expect(throws: ProjectionWireError.unknownMessageType) { try codec.decodeHostFrame(json(frame)) }
    }

    @Test func decode_whenHostTypeArrivesOnHubDirection_thenFailsClosed() throws {
        let hostData = try codec.encode(Fixture.hostFrame(.pop(appID: "a"), sequence: 1))
        let hubData = try codec.encode(Fixture.hubFrame(.hello, sequence: 1))
        #expect(throws: ProjectionWireError.unknownMessageType) { try codec.decodeHubFrame(hostData) }
        #expect(throws: ProjectionWireError.unknownMessageType) { try codec.decodeHostFrame(hubData) }
    }

    @Test func decode_whenTemplateCaseIsUnknown_thenFailsClosed() throws {
        var frame = try object(codec.encode(Fixture.hostFrame(.setRoot(appID: "a", template: Fixture.list()), sequence: 1)))
        frame["template"] = ["hologram": ["_0": ["id": "h", "title": "H"]]]
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHostFrame(json(frame)) }
    }

    @Test func decode_whenNotJSONOrHeaderMissing_thenMalformed() throws {
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHostFrame(Data("not json".utf8)) }
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(json(["type": "hello"])) }
    }

    @Test func decode_whenSessionMissing_thenMalformed() throws {
        var frame = try object(codec.encode(Fixture.hubFrame(.hello, sequence: 1)))
        frame["session"] = nil
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(json(frame)) }
    }

    @Test(arguments: ["announce", "setRoot", "push", "pop", "update", "withdraw", "present"])
    func decodeHostFrame_whenRequiredFieldMissing_thenMalformed(type: String) throws {
        let data = try json(["version": 1, "session": Fixture.hostSession.uuidString, "sequence": 1, "type": type])
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHostFrame(data) }
    }

    @Test(arguments: ["launch", "action", "reply", "mediaCommand"])
    func decodeHubFrame_whenRequiredFieldMissing_thenMalformed(type: String) throws {
        let data = try json(["version": 1, "session": Fixture.hubSession.uuidString, "sequence": 1, "type": type])
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(data) }
    }

    @Test func decodeHostFrame_whenTemplatePresentButAppIDMissing_thenMalformed() throws {
        for message in [HostToHubMessage.setRoot(appID: "a", template: Fixture.list()), .push(appID: "a", template: Fixture.list()), .update(appID: "a", template: Fixture.list())] {
            var frame = try object(codec.encode(Fixture.hostFrame(message, sequence: 1)))
            frame["appID"] = nil
            #expect(throws: ProjectionWireError.malformed) { try codec.decodeHostFrame(json(frame)) }
        }
    }

    @Test func decodeHubFrame_whenActionOrReplyIsMissingOneField_thenMalformed() throws {
        var action = try object(codec.encode(Fixture.hubFrame(.action(appID: "a", actionID: "x", payload: [:]), sequence: 1)))
        action["actionID"] = nil
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(json(action)) }
        var reply = try object(codec.encode(Fixture.hubFrame(.reply(conversationID: "c", text: "Hi"), sequence: 1)))
        reply["text"] = nil
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(json(reply)) }
    }

    @Test func decodeHubFrame_whenActionHasNoPayload_thenPayloadIsEmpty() throws {
        var action = try object(codec.encode(Fixture.hubFrame(.action(appID: "a", actionID: "x", payload: ["k": "v"]), sequence: 1)))
        action["payload"] = nil
        #expect(try codec.decodeHubFrame(json(action)).message == .action(appID: "a", actionID: "x", payload: [:]))
    }

    @Test func decodeHubFrame_whenMediaCommandIsUnknown_thenMalformed() throws {
        var frame = try object(codec.encode(Fixture.hubFrame(.mediaCommand(.play), sequence: 1)))
        frame["command"] = "selfDestruct"
        #expect(throws: ProjectionWireError.malformed) { try codec.decodeHubFrame(json(frame)) }
    }

    @Test func decodeHostFrame_whenContentBreaksLimits_thenInvalid() throws {
        var frame = try object(codec.encode(Fixture.hostFrame(.pop(appID: "a"), sequence: 1)))
        frame["appID"] = "has space"
        #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "appID"))) { try codec.decodeHostFrame(json(frame)) }
    }

    @Test func decodeHubFrame_whenContentBreaksLimits_thenInvalid() throws {
        var frame = try object(codec.encode(Fixture.hubFrame(.reply(conversationID: "c", text: "Hi"), sequence: 1)))
        frame["text"] = "   "
        #expect(throws: ProjectionWireError.invalid(.emptyText(field: "reply.text"))) { try codec.decodeHubFrame(json(frame)) }
    }

    @Test func encode_whenMessageBreaksLimits_thenInvalid() {
        let badApps = Fixture.hostFrame(.announce([Fixture.app(""),]), sequence: 1)
        #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "app.id"))) { try codec.encode(badApps) }
        let badTemplate = Fixture.hostFrame(.push(appID: "a", template: Fixture.list("")), sequence: 1)
        #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "template.id"))) { try codec.encode(badTemplate) }
        for message in [HostToHubMessage.withdraw(appID: ""), .present(appID: ""), .pop(appID: "")] {
            #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "appID"))) { try codec.encode(Fixture.hostFrame(message, sequence: 1)) }
        }
        let badLaunch = Fixture.hubFrame(.launch(appID: ""), sequence: 1)
        #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "appID"))) { try codec.encode(badLaunch) }
        let badAction = Fixture.hubFrame(.action(appID: "a", actionID: "", payload: [:]), sequence: 1)
        #expect(throws: ProjectionWireError.invalid(.invalidIdentifier(field: "actionID"))) { try codec.encode(badAction) }
    }

    @Test func encode_whenFrameExceedsPayloadCap_thenFails() {
        var limits = ProjectionLimits()
        limits.maxPayloadBytes = 200
        let small = ProjectionCodec(limits: limits)
        let frame = Fixture.hostFrame(.setRoot(appID: "a", template: Fixture.allTemplates[6]), sequence: 1)
        #expect(throws: ProjectionWireError.payloadTooLarge(limit: 200)) { try small.encode(frame) }
        #expect(small.limits == limits)
    }

    @Test func decode_whenDataExceedsPayloadCap_thenFailsWithoutParsing() throws {
        let data = try codec.encode(Fixture.hostFrame(.setRoot(appID: "a", template: Fixture.allTemplates[6]), sequence: 1))
        var limits = ProjectionLimits()
        limits.maxPayloadBytes = data.count - 1
        #expect(throws: ProjectionWireError.payloadTooLarge(limit: data.count - 1)) { try ProjectionCodec(limits: limits).decodeHostFrame(data) }
    }

    @Test func encode_whenArtworkAtCap_thenFrameFitsThePayloadCap() throws {
        let template = ProjectionTemplate.nowPlaying(NowPlayingTemplate(id: "n", title: "T", artwork: Data(count: ProjectionLimits.standard.maxArtworkBytes)))
        let data = try codec.encode(Fixture.hostFrame(.setRoot(appID: "a", template: template), sequence: 1))
        #expect(data.count <= ProjectionLimits.standard.maxPayloadBytes)
    }

    @Test func frame_whenCreatedWithoutVersion_thenUsesCurrentVersion() {
        #expect(Fixture.hubFrame(.hello, sequence: 1).version == ProjectionProtocol.currentVersion)
        #expect(ProjectionProtocol.supportedVersions.contains(ProjectionProtocol.currentVersion))
    }
}
