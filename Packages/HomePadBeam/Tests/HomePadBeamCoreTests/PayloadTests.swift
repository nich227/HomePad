import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct BeamTextTests {
    @Test func sanitizedTitle_whenControlCharactersAndLongText_thenCleansAndCaps() {
        #expect(BeamText.sanitizedTitle("  Hello\n\tWorld\u{202E}  ") == "Hello World")
        #expect(BeamText.sanitizedTitle(String(repeating: "a", count: 500))?.count == BeamText.titleLimit)
        #expect(BeamText.sanitizedTitle("\n \u{0000}") == nil)
        #expect(BeamText.sanitizedTitle(nil) == nil)
    }

    @Test func sanitizedDeviceName_whenEmptyAfterCleaning_thenUsesFallback() {
        #expect(BeamText.sanitizedDeviceName("\u{0001}\u{2028}", fallback: "iPhone") == "iPhone")
        #expect(BeamText.sanitizedDeviceName(" Ada's   iPhone ", fallback: "x") == "Ada's iPhone")
        #expect(BeamText.sanitizedDeviceName(String(repeating: "b", count: 99), fallback: "x").count == BeamText.deviceNameLimit)
        #expect(BeamText.sanitizedDeviceName("a\u{E000}b\u{0378}c", fallback: "x") == "a b c")
    }
}

@Suite struct BeamPayloadTests {
    @Test func codable_whenRoundTripped_thenEqual() throws {
        let beam = Fixture.beam()
        let decoded = try JSONDecoder().decode(BeamPayload.self, from: JSONEncoder().encode(beam))
        #expect(decoded == beam)
        #expect(decoded.kind == .website)
    }

    @Test func decode_whenKindUnknownOrMissing_thenWebsite() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixture.beam())) as? [String: Any])
        object["kind"] = "hologram"
        #expect(try JSONDecoder().decode(BeamPayload.self, from: JSONSerialization.data(withJSONObject: object)).kind == .website)
        object["kind"] = nil
        #expect(try JSONDecoder().decode(BeamPayload.self, from: JSONSerialization.data(withJSONObject: object)).kind == .website)
        object["kind"] = "recipe"
        #expect(try JSONDecoder().decode(BeamPayload.self, from: JSONSerialization.data(withJSONObject: object)).kind == .recipe)
    }

    @Test func decode_whenTitleHasControlCharacters_thenSanitized() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Fixture.beam())) as? [String: Any])
        object["title"] = "Line one\nLine two"
        let decoded = try JSONDecoder().decode(BeamPayload.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.title == "Line one Line two")
    }

    @Test func attributed_whenGivenAuthenticatedDevice_thenReplacesClaimedSender() {
        let beam = Fixture.beam(sender: Fixture.otherPhone)
        let fixed = beam.attributed(to: Fixture.phone)
        #expect(fixed.sender == Fixture.phone)
        #expect(fixed.id == beam.id)
        #expect(fixed.url == beam.url)
    }

    @Test(arguments: [
        BeamOutcome.opened, .awaitingApproval, .waitingForOwner, .expired, .declined, .rateLimited, .unknown, .rejected(.localHost), .rejected(.unsupportedScheme),
    ])
    func receipt_whenRoundTripped_thenEqual(outcome: BeamOutcome) throws {
        let receipt = BeamReceipt(beamID: Fixture.phoneID, outcome: outcome)
        #expect(try JSONDecoder().decode(BeamReceipt.self, from: JSONEncoder().encode(receipt)) == receipt)
    }

    @Test func receipt_whenStatusOrReasonUnknown_thenDegradesSafely() throws {
        let id = Fixture.phoneID.uuidString
        let future = Data(#"{"beamID":"\#(id)","status":"teleported"}"#.utf8)
        #expect(try JSONDecoder().decode(BeamReceipt.self, from: future).outcome == .unknown)
        let oddReason = Data(#"{"beamID":"\#(id)","status":"rejected","reason":"new"}"#.utf8)
        #expect(try JSONDecoder().decode(BeamReceipt.self, from: oddReason).outcome == .rejected(.malformed))
        let noReason = Data(#"{"beamID":"\#(id)","status":"rejected"}"#.utf8)
        #expect(try JSONDecoder().decode(BeamReceipt.self, from: noReason).outcome == .rejected(.malformed))
    }

    @Test func message_whenRoundTripped_thenEqual() throws {
        for content in [BeamMessage.Content.beam(Fixture.beam()), .receipt(BeamReceipt(beamID: Fixture.phoneID, outcome: .opened))] {
            let message = BeamMessage(content)
            #expect(try JSONDecoder().decode(BeamMessage.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test func message_whenVersionWrongOrEmpty_thenThrows() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BeamMessage.self, from: Data(#"{"v":2,"receipt":{}}"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BeamMessage.self, from: Data(#"{"v":1}"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BeamMessage.self, from: Data(#"{"beam":{}}"#.utf8)) }
    }

    @Test func message_whenURLIsNotAStringURL_thenThrows() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(BeamMessage(.beam(Fixture.beam())))) as? [String: Any])
        var beam = try #require(object["beam"] as? [String: Any])
        beam["url"] = ""
        object["beam"] = beam
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BeamMessage.self, from: data) }
    }
}

@Suite struct BeamDeliveryStateTests {
    let id = Fixture.phoneID

    @Test func applying_whenReceiptMatches_thenMovesToDelivered() {
        let opened = BeamReceipt(beamID: id, outcome: .opened)
        #expect(BeamDeliveryState.sending.applying(opened, to: id) == .delivered(.opened))
        #expect(BeamDeliveryState.delivered(.awaitingApproval).applying(opened, to: id) == .delivered(.opened))
        #expect(BeamDeliveryState.delivered(.waitingForOwner).applying(opened, to: id) == .delivered(.opened))
        #expect(BeamDeliveryState.failed(.noReceipt).applying(opened, to: id) == .delivered(.opened))
        let expired = BeamReceipt(beamID: id, outcome: .expired)
        #expect(BeamDeliveryState.delivered(.waitingForOwner).applying(expired, to: id) == .delivered(.expired))
    }

    @Test func applying_whenReceiptIsForAnotherBeamOrStateIsFinal_thenUnchanged() {
        let opened = BeamReceipt(beamID: id, outcome: .opened)
        #expect(BeamDeliveryState.sending.applying(opened, to: Fixture.hubID) == .sending)
        #expect(BeamDeliveryState.idle.applying(opened, to: id) == .idle)
        #expect(BeamDeliveryState.delivered(.declined).applying(opened, to: id) == .delivered(.declined))
        #expect(BeamDeliveryState.failed(.hubUnreachable).applying(opened, to: id) == .failed(.hubUnreachable))
    }

    @Test func isSuccess_whenOpenedOrWaiting_thenTrue() {
        #expect(BeamDeliveryState.delivered(.opened).isSuccess)
        #expect(BeamDeliveryState.delivered(.awaitingApproval).isSuccess)
        #expect(BeamDeliveryState.delivered(.waitingForOwner).isSuccess)
        #expect(!BeamDeliveryState.delivered(.expired).isSuccess)
        #expect(!BeamDeliveryState.delivered(.rateLimited).isSuccess)
        #expect(!BeamDeliveryState.sending.isSuccess)
        #expect(!BeamDeliveryState.failed(.noPairedHub).isSuccess)
    }
}
