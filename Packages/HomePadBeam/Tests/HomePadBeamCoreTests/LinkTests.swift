import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct FrameCodecTests {
    @Test func encode_whenBodyGiven_thenPrefixesBigEndianLength() throws {
        let frame = try FrameCodec.encode(Data([9, 8, 7]), limit: 10)
        #expect([UInt8](frame) == [0, 0, 0, 3, 9, 8, 7])
    }

    @Test func encode_whenEmptyOrOverLimit_thenThrows() {
        #expect(throws: FrameError.empty) { try FrameCodec.encode(Data(), limit: 10) }
        #expect(throws: FrameError.tooLarge(declared: 11, limit: 10)) { try FrameCodec.encode(Data(count: 11), limit: 10) }
    }

    @Test func next_whenStreamCutAtEveryBoundary_thenYieldsSameFrames() throws {
        let bodies = [Data([1]), Data((0..<200).map { UInt8($0) }), Data([0xFF, 0x00])]
        let stream = try bodies.map { try FrameCodec.encode($0, limit: 1000) }.reduce(Data(), +)
        for chunkSize in 1...stream.count {
            var decoder = FrameDecoder(limit: 1000)
            var decoded: [Data] = []
            var offset = 0
            while offset < stream.count {
                decoder.append(stream.subdata(in: offset..<min(offset + chunkSize, stream.count)))
                offset += chunkSize
                while let body = try decoder.next() {
                    decoded.append(body)
                }
            }
            #expect(decoded == bodies, "chunk size \(chunkSize)")
            #expect(decoder.bufferedByteCount == 0)
        }
    }

    @Test func next_whenDeclaredLengthOverLimit_thenFailsBeforeBodyArrives() {
        var decoder = FrameDecoder(limit: 16)
        decoder.append(Data([0, 0, 0, 17]))
        #expect(throws: FrameError.tooLarge(declared: 17, limit: 16)) { try decoder.next() }
        #expect(decoder.bufferedByteCount == 0)
        decoder.append(Data([0, 0, 0, 1, 5]))
        #expect(decoder.bufferedByteCount == 0)
        #expect(throws: FrameError.closed) { try decoder.next() }
    }

    @Test func next_whenLengthIsHuge_thenRejects() {
        var decoder = FrameDecoder(limit: 1024)
        decoder.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        #expect(throws: FrameError.tooLarge(declared: 4_294_967_295, limit: 1024)) { try decoder.next() }
    }

    @Test func next_whenZeroLength_thenFails() {
        var decoder = FrameDecoder(limit: 16)
        decoder.append(Data([0, 0, 0, 0]))
        #expect(throws: FrameError.empty) { try decoder.next() }
    }

    @Test func next_whenLimitRaised_thenAcceptsLargerFrame() throws {
        var decoder = FrameDecoder(limit: 2)
        decoder.limit = 8
        decoder.append(try FrameCodec.encode(Data(count: 8), limit: 8))
        #expect(try decoder.next()?.count == 8)
        #expect(try decoder.next() == nil)
    }
}

@Suite struct LinkMessageTests {
    @Test(arguments: [
        LinkMessage.hello(LinkHello(device: Fixture.phone, proof: Data([1, 2, 3]))),
        .envelope(channel: "beam", payload: Data([0, 1, 2, 255])),
        .envelope(channel: "presence", payload: Data()),
        .envelope(channel: String(repeating: "c", count: 64), payload: Data([1])),
        .ping(0), .ping(.max), .pong(0x0102030405060708),
        .bye(.normal), .bye(.revoked), .bye(.unknown),
    ])
    func encoded_whenDecoded_thenEqual(message: LinkMessage) throws {
        #expect(try LinkMessage(decoding: message.encoded()) == message)
    }

    @Test func encoded_whenPing_thenVersionTypeAndBigEndianNonce() throws {
        #expect([UInt8](try LinkMessage.ping(0x0102030405060708).encoded()) == [1, 3, 1, 2, 3, 4, 5, 6, 7, 8])
        #expect([UInt8](try LinkMessage.bye(.replaced).encoded()) == [1, 5, 3])
    }

    @Test func encoded_whenChannelEmptyOrTooLong_thenThrows() {
        #expect(throws: LinkMessageError.invalidChannel) { try LinkMessage.envelope(channel: "", payload: Data()).encoded() }
        #expect(throws: LinkMessageError.invalidChannel) { try LinkMessage.envelope(channel: String(repeating: "c", count: 65), payload: Data()).encoded() }
    }

    @Test(arguments: [
        ([UInt8](), LinkMessageError.truncated),
        ([1], .truncated),
        ([2, 1, 0], .unsupportedVersion(2)),
        ([1, 0], .unknownType(0)),
        ([1, 99], .unknownType(99)),
        ([1, 1, 0x7B], .invalidHello),
        ([1, 1], .invalidHello),
        ([1, 2], .invalidChannel),
        ([1, 2, 0], .invalidChannel),
        ([1, 2, 5, 0x61], .invalidChannel),
        ([1, 2, 65] + [UInt8](repeating: 0x61, count: 65), .invalidChannel),
        ([1, 2, 2, 0xFF, 0xFE], .invalidChannel),
        ([1, 3, 1, 2, 3], .invalidBody),
        ([1, 4, 1, 2, 3, 4, 5, 6, 7, 8, 9], .invalidBody),
        ([1, 5], .invalidBody),
        ([1, 5, 0, 0], .invalidBody),
    ])
    func decoding_whenMalformed_thenThrowsTypedError(bytes: [UInt8], error: LinkMessageError) {
        #expect(throws: error) { try LinkMessage(decoding: Data(bytes)) }
    }

    @Test func decoding_whenByeReasonUnknown_thenMapsToUnknown() throws {
        #expect(try LinkMessage(decoding: Data([1, 5, 77])) == .bye(.unknown))
    }
}

@Suite struct LinkSessionTests {
    let peer = Fixture.phoneID

    private func frame(_ message: LinkMessage) throws -> Data {
        try LinkSession.frame(message)
    }

    private func established() throws -> LinkSession {
        var session = LinkSession()
        _ = session.receive(try frame(.hello(LinkHello(device: Fixture.phone, proof: Data()))))
        _ = session.establish(peerID: peer)
        return session
    }

    @Test func receive_whenFirstFrameIsHello_thenEmitsHelloAndWaits() throws {
        var session = LinkSession()
        let hello = LinkHello(device: Fixture.phone, proof: Data([1]))
        #expect(session.receive(try frame(.hello(hello))) == [.hello(hello)])
        #expect(session.phase == .authenticating)
    }

    @Test(arguments: [
        LinkMessage.envelope(channel: "beam", payload: Data([1])), .ping(1), .pong(1),
    ])
    func receive_whenFirstFrameIsNotHello_thenClosesWithoutDelivering(message: LinkMessage) throws {
        var session = LinkSession()
        #expect(session.receive(try frame(message)) == [.close(.protocolViolation)])
        #expect(session.phase == .closed)
        #expect(session.receive(try frame(.hello(LinkHello(device: Fixture.phone, proof: Data())))) == [])
    }

    @Test func receive_whenEnvelopeFollowsHelloInSameChunk_thenHeldUntilEstablished() throws {
        var session = LinkSession()
        let hello = LinkHello(device: Fixture.phone, proof: Data())
        let big = Data(repeating: 7, count: LinkLimits.helloFrameLimit * 2)
        let bytes = try frame(.hello(hello)) + frame(.envelope(channel: "beam", payload: big)) + frame(.ping(5))
        #expect(session.receive(bytes) == [.hello(hello)])
        let events = session.establish(peerID: peer)
        #expect(events == [
            .envelope(PeerEnvelope(channel: "beam", sender: peer, payload: big)),
            .reply(try frame(.pong(5))),
        ])
        #expect(session.phase == .established(peer))
    }

    @Test func receive_whenEstablished_thenStampsAuthenticatedSender() throws {
        var session = try established()
        let events = session.receive(try frame(.envelope(channel: "presence", payload: Data([4, 2]))))
        #expect(events == [.envelope(PeerEnvelope(channel: "presence", sender: peer, payload: Data([4, 2])))])
        #expect(session.receive(try frame(.pong(9))) == [.pong(9)])
    }

    @Test func receive_whenHelloOversized_thenCloses() throws {
        var session = LinkSession(helloFrameLimit: 32, frameLimit: 1024)
        let hello = LinkHello(device: Fixture.phone, proof: Data(repeating: 1, count: 64))
        #expect(session.receive(try frame(.hello(hello))) == [.close(.protocolViolation)])
    }

    @Test func receive_whenFrameOverLimitAfterEstablish_thenCloses() throws {
        var session = LinkSession(helloFrameLimit: 512, frameLimit: 600)
        _ = session.receive(try frame(.hello(LinkHello(device: Fixture.phone, proof: Data()))))
        _ = session.establish(peerID: peer)
        let ok = try frame(.envelope(channel: "beam", payload: Data(count: 500)))
        let delivered = session.receive(ok)
        #expect(delivered.count == 1)
        let tooBig = try frame(.envelope(channel: "beam", payload: Data(count: 700)))
        #expect(session.receive(Data(tooBig.prefix(4))) == [.close(.protocolViolation)])
        #expect(session.phase == .closed)
    }

    @Test func receive_whenGarbageOrSecondHello_thenCloses() throws {
        var session = try established()
        #expect(session.receive(Data([0, 0, 0, 2, 9, 9])) == [.close(.protocolViolation)])
        var second = try established()
        let again = try frame(.hello(LinkHello(device: Fixture.phone, proof: Data())))
        #expect(second.receive(try frame(.envelope(channel: "beam", payload: Data())) + again) == [
            .envelope(PeerEnvelope(channel: "beam", sender: peer, payload: Data())),
            .close(.protocolViolation),
        ])
    }

    @Test func receive_whenBye_thenClosesWithPeerReason() throws {
        var session = try established()
        #expect(session.receive(try frame(.bye(.shuttingDown)) + frame(.ping(1))) == [.close(.shuttingDown)])
        var early = LinkSession()
        #expect(early.receive(try frame(.bye(.normal))) == [.close(.normal)])
    }

    @Test func receive_whenBytesArriveWhileAuthenticating_thenBuffersUpToLimit() throws {
        var session = LinkSession(helloFrameLimit: 512, frameLimit: 64)
        _ = session.receive(try frame(.hello(LinkHello(device: Fixture.phone, proof: Data()))))
        #expect(session.receive(Data(count: 60)) == [])
        #expect(session.phase == .authenticating)
        #expect(session.receive(Data(count: 60)) == [.close(.protocolViolation)])
    }

    @Test func establish_whenNotAuthenticating_thenNoEffect() throws {
        var session = LinkSession()
        #expect(session.establish(peerID: peer) == [])
        #expect(session.phase == .awaitingHello)
        session.close()
        #expect(session.phase == .closed)
        #expect(session.receive(Data([1])) == [])
    }

    @Test func frame_whenMessageOrSizeInvalid_thenThrowsTyped() {
        #expect(throws: LinkFramingError.message(.invalidChannel)) { try LinkSession.frame(.envelope(channel: "", payload: Data())) }
        #expect(throws: LinkFramingError.frame(.tooLarge(declared: 107, limit: 100))) {
            try LinkSession.frame(.envelope(channel: "beam", payload: Data(count: 100)), limit: 100)
        }
    }

    @Test func canAccept_whenAtLimits_thenRefuses() {
        #expect(LinkLimits.canAccept(total: 0, unauthenticated: 0))
        #expect(LinkLimits.canAccept(total: LinkLimits.maximumConnections - 1, unauthenticated: LinkLimits.maximumUnauthenticatedConnections - 1))
        #expect(!LinkLimits.canAccept(total: LinkLimits.maximumConnections, unauthenticated: 0))
        #expect(!LinkLimits.canAccept(total: 1, unauthenticated: LinkLimits.maximumUnauthenticatedConnections))
    }
}

@Suite struct AuthenticatorTests {
    let record = Fixture.paired()

    private func hello(_ device: PeerDevice = Fixture.phone, keys: LinkKeys) -> LinkHello {
        CompanionAuthenticator.hello(companion: device, keys: keys)
    }

    @Test func admit_whenPairedDeviceProvesItsKey_thenKnownWithHubSideRecord() throws {
        var stored = record
        stored.device.profileID = Fixture.profileID
        var claimed = Fixture.phone
        claimed.name = "Renamed\nPhone"
        claimed.profileID = Fixture.hubID
        let result = HubAuthenticator.admit(hello: hello(claimed, keys: stored.keys), hubID: Fixture.hubID, paired: [stored], invitation: nil, now: Fixture.now)
        let admission = try result.get()
        #expect(admission == .known(admission.record))
        #expect(admission.record.device.name == "Renamed Phone")
        #expect(admission.record.device.profileID == Fixture.profileID)
        #expect(admission.record.secret == stored.secret)
    }

    @Test func admit_whenPairedDeviceClaimsAnotherDevicesID_thenRejected() {
        let other = Fixture.paired(Fixture.otherPhone, fill: 2)
        let forged = LinkHello(device: Fixture.otherPhone, proof: record.keys.proof(deviceID: Fixture.otherPhoneID, role: .companion))
        let result = HubAuthenticator.admit(hello: forged, hubID: Fixture.hubID, paired: [record, other], invitation: nil, now: Fixture.now)
        #expect(result == .failure(.invalidProof))
    }

    @Test func admit_whenDeviceUnknownOrRevoked_thenRejected() {
        let result = HubAuthenticator.admit(hello: hello(keys: record.keys), hubID: Fixture.hubID, paired: [], invitation: nil, now: Fixture.now)
        #expect(result == .failure(.unknownDevice))
    }

    @Test func admit_whenRoleIsHub_thenRejected() {
        let hub = PeerDevice(id: Fixture.phoneID, name: "x", role: .hub)
        let result = HubAuthenticator.admit(hello: hello(hub, keys: record.keys), hubID: Fixture.hubID, paired: [record], invitation: nil, now: Fixture.now)
        #expect(result == .failure(.wrongRole))
    }

    @Test func admit_whenNewDeviceUsesOpenInvitation_thenPairedWithHubChosenProfile() throws {
        let invitation = Fixture.invitation()
        var claimed = Fixture.otherPhone
        claimed.profileID = Fixture.hubID
        claimed.name = ""
        let result = HubAuthenticator.admit(hello: hello(claimed, keys: invitation.invitation.keys), hubID: Fixture.hubID, paired: [record], invitation: invitation, now: Fixture.now)
        guard case .newlyPaired(let created) = try result.get() else {
            Issue.record("expected a new pairing")
            return
        }
        #expect(created.device == PeerDevice(id: Fixture.otherPhoneID, name: "iPhone", role: .companion, profileID: Fixture.profileID))
        #expect(created.secret == invitation.invitation.secret)
        #expect(created.hubID == Fixture.hubID)
        #expect(created.pairedAt == Fixture.now)
        #expect(created.approvedBeamCount == 0)
    }

    @Test func admit_whenInvitationExpiredOrProofWrong_thenRejected() {
        let invitation = Fixture.invitation(expiresIn: 10)
        let good = hello(Fixture.otherPhone, keys: invitation.invitation.keys)
        let late = HubAuthenticator.admit(hello: good, hubID: Fixture.hubID, paired: [], invitation: invitation, now: Fixture.now.addingTimeInterval(10))
        #expect(late == .failure(.unknownDevice))
        let wrong = hello(Fixture.otherPhone, keys: Fixture.paired(fill: 77).keys)
        let bad = HubAuthenticator.admit(hello: wrong, hubID: Fixture.hubID, paired: [], invitation: invitation, now: Fixture.now)
        #expect(bad == .failure(.unknownDevice))
    }

    @Test func admit_whenPairedDeviceScansNewInvitation_thenRepairedWithNewSecret() throws {
        let invitation = Fixture.invitation()
        let result = HubAuthenticator.admit(hello: hello(keys: invitation.invitation.keys), hubID: Fixture.hubID, paired: [record], invitation: invitation, now: Fixture.now)
        guard case .newlyPaired(let created) = try result.get() else {
            Issue.record("expected a new pairing")
            return
        }
        #expect(created.id == record.id)
        #expect(created.secret != record.secret)
    }

    @Test func verify_whenHubAnswersWithMatchingProof_thenAccepted() throws {
        let hubHello = HubAuthenticator.hello(hub: PeerDevice(id: Fixture.hubID, name: " Kitchen\n", role: .hub, profileID: Fixture.profileID), keys: record.keys)
        let hub = try CompanionAuthenticator.verify(hubHello: hubHello, expectedHubID: Fixture.hubID, keys: record.keys).get()
        #expect(hub == PeerDevice(id: Fixture.hubID, name: "Kitchen", role: .hub))
    }

    @Test func verify_whenHubHelloIsWrong_thenRejected() {
        let keys = record.keys
        let good = HubAuthenticator.hello(hub: Fixture.hub, keys: keys)
        #expect(CompanionAuthenticator.verify(hubHello: good, expectedHubID: Fixture.phoneID, keys: keys) == .failure(.wrongHub))
        let reflected = hello(keys: keys)
        #expect(CompanionAuthenticator.verify(hubHello: reflected, expectedHubID: Fixture.phoneID, keys: keys) == .failure(.wrongRole))
        let otherKeys = HubAuthenticator.hello(hub: Fixture.hub, keys: Fixture.paired(fill: 3).keys)
        #expect(CompanionAuthenticator.verify(hubHello: otherKeys, expectedHubID: Fixture.hubID, keys: keys) == .failure(.invalidProof))
        let companionProof = LinkHello(device: Fixture.hub, proof: keys.proof(deviceID: Fixture.hubID, role: .companion))
        #expect(CompanionAuthenticator.verify(hubHello: companionProof, expectedHubID: Fixture.hubID, keys: keys) == .failure(.invalidProof))
    }
}

@Suite struct ListenerPlanTests {
    private func plan(active: Bool = true, receive: Bool = true, paired: [PairedDevice] = [Fixture.paired()], invitation: PendingInvitation? = nil, now: Date = Fixture.now) -> ListenerPlan? {
        ListenerPlan.make(sceneActive: active, receiveEnabled: receive, hubID: Fixture.hubID, hubName: "Kitchen", paired: paired, invitation: invitation, now: now)
    }

    @Test func make_whenNothingPairedAndNoInvitation_thenNoListener() {
        #expect(plan(paired: []) == nil)
    }

    @Test func make_whenSceneInactive_thenNoListener() {
        #expect(plan(active: false, invitation: Fixture.invitation()) == nil)
    }

    @Test func make_whenReceiveOff_thenNoListenerEvenWithPairedDevices() {
        #expect(plan(receive: false) == nil)
    }

    @Test func make_whenReceiveOnAndPaired_thenOneCredentialPerDevice() throws {
        let devices = [Fixture.paired(), Fixture.paired(Fixture.otherPhone, fill: 2)]
        let made = try #require(plan(paired: devices))
        #expect(made.credentials == devices.map(\.keys.credential))
        #expect(made.advertisement == HubAdvertisement(hubID: Fixture.hubID, name: "Kitchen"))
    }

    @Test func make_whenInvitationOpen_thenListensForItEvenWithReceiveOff() throws {
        let invitation = Fixture.invitation()
        let made = try #require(plan(receive: false, invitation: invitation))
        #expect(made.credentials == [invitation.invitation.keys.credential])
        let both = try #require(plan(invitation: invitation))
        #expect(both.credentials.count == 2)
    }

    @Test func make_whenInvitationExpired_thenItsKeyIsNotInstalled() throws {
        let invitation = Fixture.invitation(expiresIn: 5)
        #expect(plan(paired: [], invitation: invitation, now: Fixture.now.addingTimeInterval(5)) == nil)
        let made = try #require(plan(invitation: invitation, now: Fixture.now.addingTimeInterval(6)))
        #expect(made.credentials.count == 1)
    }

    @Test func make_whenInvitationSecretAlreadyPaired_thenNoDuplicateIdentity() throws {
        let invitation = Fixture.invitation(fill: 1)
        let made = try #require(plan(invitation: invitation))
        #expect(made.credentials.count == 1)
    }

    @Test func advertisement_whenBuilt_thenCarriesOnlyIDVersionAndName() {
        let advertisement = HubAdvertisement(hubID: Fixture.hubID, name: " Kitchen\u{0007} ")
        #expect(advertisement.name == "Kitchen")
        #expect(advertisement.txtRecord == ["id": Fixture.hubID.uuidString, "v": "1"])
        #expect(HubAdvertisement(hubID: Fixture.hubID, name: "").name == "HomePad")
    }

    @Test func parse_whenRecordValidOrNot_thenAdvertisementOrNil() {
        let record = HubAdvertisement(hubID: Fixture.hubID, name: "Kitchen").txtRecord
        #expect(HubAdvertisement.parse(serviceName: "Kitchen", txtRecord: record) == HubAdvertisement(hubID: Fixture.hubID, name: "Kitchen"))
        #expect(HubAdvertisement.parse(serviceName: "Kitchen", txtRecord: ["id": Fixture.hubID.uuidString, "v": "2"]) == nil)
        #expect(HubAdvertisement.parse(serviceName: "Kitchen", txtRecord: ["id": "nope", "v": "1"]) == nil)
        #expect(HubAdvertisement.parse(serviceName: "Kitchen", txtRecord: ["v": "1"]) == nil)
        #expect(HubAdvertisement.parse(serviceName: "Kitchen", txtRecord: [:]) == nil)
    }
}

@Suite struct EnvelopeFanoutTests {
    @Test func publish_whenSubscribed_thenDeliversOnlyThatChannel() async {
        let fanout = EnvelopeFanout()
        let beams = fanout.subscribe(to: "beam")
        let second = fanout.subscribe(to: "beam")
        let presence = fanout.subscribe(to: "presence")
        #expect(fanout.subscriberCount(for: "beam") == 2)
        let envelope = PeerEnvelope(channel: "beam", sender: Fixture.phoneID, payload: Data([1]))
        fanout.publish(envelope)
        fanout.publish(PeerEnvelope(channel: "nobody", sender: Fixture.phoneID, payload: Data()))
        fanout.finishAll()
        var received: [PeerEnvelope] = []
        for await item in beams { received.append(item) }
        for await item in second { received.append(item) }
        var other: [PeerEnvelope] = []
        for await item in presence { other.append(item) }
        #expect(received == [envelope, envelope])
        #expect(other.isEmpty)
        #expect(fanout.subscriberCount(for: "beam") == 0)
    }

    @Test func subscribe_whenStreamDropped_thenSubscriberRemoved() async {
        let fanout = EnvelopeFanout()
        do {
            let stream = fanout.subscribe(to: "beam")
            let task = Task { for await _ in stream {} }
            #expect(fanout.subscriberCount(for: "beam") == 1)
            task.cancel()
            await task.value
        }
        #expect(fanout.subscriberCount(for: "beam") == 0)
    }

    @Test func publish_whenSubscriberDoesNotRead_thenKeepsNewestOnly() async {
        let fanout = EnvelopeFanout()
        let stream = fanout.subscribe(to: "beam")
        for index in 0..<(EnvelopeFanout.bufferLimit + 10) {
            fanout.publish(PeerEnvelope(channel: "beam", sender: Fixture.phoneID, payload: Data([UInt8(index % 256)])))
        }
        fanout.finishAll()
        var count = 0
        var first: PeerEnvelope?
        for await item in stream {
            if first == nil { first = item }
            count += 1
        }
        #expect(count == EnvelopeFanout.bufferLimit)
        #expect(first?.payload == Data([10]))
    }
}
