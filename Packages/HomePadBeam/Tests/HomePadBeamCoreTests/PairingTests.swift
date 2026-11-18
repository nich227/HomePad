import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct PairingSecretTests {
    @Test func init_whenLengthIsNot32_thenThrows() {
        #expect(throws: PairingSecretError.wrongLength(31)) { try PairingSecret(bytes: Data(repeating: 0, count: 31)) }
        #expect(throws: PairingSecretError.wrongLength(0)) { try PairingSecret(bytes: Data()) }
    }

    @Test func generate_whenRandomSourceReturnsTooFewBytes_thenThrowsInsteadOfWeakSecret() {
        #expect(throws: PairingSecretError.wrongLength(31)) { try PairingSecret.generate(using: FixedRandom(shortBy: 1)) }
        var session = PairingSession()
        #expect(throws: PairingSecretError.wrongLength(31)) {
            try session.open(hubID: Fixture.hubID, hubName: "K", profileID: nil, now: Fixture.now, random: FixedRandom(shortBy: 1))
        }
        #expect(session.active(at: Fixture.now) == nil)
    }

    @Test func generate_whenSystemRandom_thenThirtyTwoBytesAndDistinct() throws {
        let first = try PairingSecret.generate(using: SystemRandomSource())
        let second = try PairingSecret.generate(using: SystemRandomSource())
        #expect(first.bytes.count == 32)
        #expect(first != second)
        #expect(SystemRandomSource().bytes(5).count == 5)
    }

    @Test func description_whenPrintedOrDumped_thenNeverShowsBytes() {
        let secret = Fixture.secret(0xAB)
        var dumped = ""
        dump(secret, to: &dumped)
        let texts = ["\(secret)", String(reflecting: secret), dumped, "\(secret.customMirror.children.count)"]
        for text in texts {
            #expect(!text.lowercased().contains("abab"))
            #expect(!text.contains("171"))
            #expect(!text.contains(secret.bytes.base64EncodedString()))
        }
        #expect(secret.description == "PairingSecret(redacted)")
        #expect(secret.debugDescription == secret.description)
    }

    @Test func codable_whenRoundTrippedOrWrongLength_thenValidates() throws {
        let secret = Fixture.secret(3)
        let data = try JSONEncoder().encode([secret])
        #expect(try JSONDecoder().decode([PairingSecret].self, from: data) == [secret])
        let short = try JSONEncoder().encode([Data(repeating: 1, count: 8)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([PairingSecret].self, from: short) }
    }
}

@Suite struct LinkKeysTests {
    @Test func derive_whenKnownInputs_thenMatchesIndependentHKDF() {
        let keys = LinkKeys.derive(secret: Fixture.sequentialSecret, hubID: Fixture.hubID)
        let hex = { (data: Data) in data.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(keys.credential.key) == "6f6bd6b204769909b8867a2bd6a35da845dcb34294562ead1cac440bb4e06024")
        #expect(String(decoding: keys.credential.identity, as: UTF8.self) == "cf102e931059d7552f3bf4b7a4742ebc")
        #expect(hex(keys.proof(deviceID: Fixture.phoneID, role: .companion)) == "33a5f87c41ec4a9a84711db2e3457d8b3fac98785a756c86df1f416b422e32bc")
    }

    @Test func derive_whenSecretOrHubDiffers_thenEverythingDiffers() {
        let base = LinkKeys.derive(secret: Fixture.secret(1), hubID: Fixture.hubID)
        let otherSecret = LinkKeys.derive(secret: Fixture.secret(2), hubID: Fixture.hubID)
        let otherHub = LinkKeys.derive(secret: Fixture.secret(1), hubID: Fixture.phoneID)
        #expect(base == LinkKeys.derive(secret: Fixture.secret(1), hubID: Fixture.hubID))
        for other in [otherSecret, otherHub] {
            #expect(base.credential.key != other.credential.key)
            #expect(base.credential.identity != other.credential.identity)
            #expect(base.proof(deviceID: Fixture.phoneID, role: .companion) != other.proof(deviceID: Fixture.phoneID, role: .companion))
        }
        #expect(base.credential.key != Fixture.secret(1).bytes)
        #expect(base.credential.key.count == 32)
        #expect(base.credential.identity.count == 32)
    }

    @Test func isValidProof_whenDeviceRoleOrKeyDiffers_thenFalse() {
        let keys = LinkKeys.derive(secret: Fixture.secret(1), hubID: Fixture.hubID)
        let proof = keys.proof(deviceID: Fixture.phoneID, role: .companion)
        #expect(keys.isValidProof(proof, deviceID: Fixture.phoneID, role: .companion))
        #expect(!keys.isValidProof(proof, deviceID: Fixture.otherPhoneID, role: .companion))
        #expect(!keys.isValidProof(proof, deviceID: Fixture.phoneID, role: .hub))
        #expect(!keys.isValidProof(Data(proof.dropLast()), deviceID: Fixture.phoneID, role: .companion))
        #expect(!keys.isValidProof(Data(), deviceID: Fixture.phoneID, role: .companion))
        let otherKeys = LinkKeys.derive(secret: Fixture.secret(2), hubID: Fixture.hubID)
        #expect(!otherKeys.isValidProof(proof, deviceID: Fixture.phoneID, role: .companion))
    }

    @Test func description_whenPrinted_thenRedacted() {
        let keys = LinkKeys.derive(secret: Fixture.secret(1), hubID: Fixture.hubID)
        var dumped = ""
        dump(keys, to: &dumped)
        dump(keys.credential, to: &dumped)
        #expect("\(keys)" == "LinkKeys(redacted)")
        #expect("\(keys.credential)" == "LinkCredential(redacted)")
        #expect(!dumped.contains("bytes"))
        #expect(LinkCredential(identity: Data([1]), key: Data([2])).key == Data([2]))
    }

    @Test func uuidRawBytes_whenRoundTripped_thenEqualAndRejectsWrongLength() {
        #expect(UUID(rawBytes: Fixture.hubID.rawBytes) == Fixture.hubID)
        #expect(Fixture.hubID.rawBytes.last == 0xAA)
        #expect(UUID(rawBytes: Data(repeating: 0, count: 15)) == nil)
    }
}

@Suite struct PairingInvitationTests {
    let invitation = PairingInvitation(hubID: Fixture.hubID, hubName: "Kitchen", secret: Fixture.secret(5), expiresAt: Fixture.now.addingTimeInterval(120.7))

    @Test func code_whenParsed_thenRoundTrips() throws {
        let code = invitation.code
        #expect(code.hasPrefix("homepad://pair?c="))
        #expect(!code.contains("=", after: "homepad://pair?c="))
        #expect(!code.contains("+") && !code.contains("/", after: "homepad://pair?c="))
        let parsed = try PairingInvitation.parse("  \(code)\n", now: Fixture.now)
        #expect(parsed == invitation)
        #expect(parsed.expiresAt == Fixture.now.addingTimeInterval(120))
        #expect(parsed.keys == LinkKeys.derive(secret: Fixture.secret(5), hubID: Fixture.hubID))
    }

    @Test func code_whenHubNameIsLongOrEmpty_thenFitsOrFallsBack() throws {
        let long = PairingInvitation(hubID: Fixture.hubID, hubName: String(repeating: "é", count: 40), secret: Fixture.secret(), expiresAt: Fixture.now.addingTimeInterval(60))
        #expect(long.hubName.utf8.count <= PairingInvitation.hubNameByteLimit)
        #expect(try PairingInvitation.parse(long.code, now: Fixture.now) == long)
        let empty = PairingInvitation(hubID: Fixture.hubID, hubName: " \n", secret: Fixture.secret(), expiresAt: Fixture.now.addingTimeInterval(60))
        #expect(empty.hubName == "HomePad")
    }

    @Test func code_whenExpiryOutOfRange_thenClamps() {
        let past = PairingInvitation(hubID: Fixture.hubID, hubName: "K", secret: Fixture.secret(), expiresAt: Date(timeIntervalSince1970: -5))
        #expect(past.expiresAt == Date(timeIntervalSince1970: 0))
        let far = PairingInvitation(hubID: Fixture.hubID, hubName: "K", secret: Fixture.secret(), expiresAt: .distantFuture)
        #expect(far.expiresAt == Date(timeIntervalSince1970: Double(UInt32.max)))
    }

    @Test func parse_whenExpired_thenThrowsExpired() {
        #expect(throws: PairingInvitationError.expired) { try PairingInvitation.parse(invitation.code, now: Fixture.now.addingTimeInterval(120)) }
        #expect(invitation.isExpired(at: Fixture.now.addingTimeInterval(121)))
        #expect(!invitation.isExpired(at: Fixture.now.addingTimeInterval(119)))
    }

    @Test(arguments: [
        "https://example.com", "homepad://beam?url=x", "homepad://pair", "pair?c=abc", "",
    ])
    func parse_whenNotAnInvitation_thenThrows(text: String) {
        #expect(throws: PairingInvitationError.notAnInvitation) { try PairingInvitation.parse(text, now: Fixture.now) }
    }

    @Test(arguments: ["", "!!!!", "abc$", "A", "AAAAA", "AA==", "AA+/"])
    func parse_whenNotBase64URL_thenThrowsInvalidEncoding(body: String) {
        #expect(throws: PairingInvitationError.invalidEncoding) { try PairingInvitation.parse("homepad://pair?c=\(body)", now: Fixture.now) }
    }

    private func mutated(_ change: (inout [UInt8]) -> Void) -> String {
        var bytes = [UInt8](Base64URL.decode(String(invitation.code.dropFirst("homepad://pair?c=".count))) ?? Data())
        change(&bytes)
        return "homepad://pair?c=" + Base64URL.encode(Data(bytes))
    }

    @Test func parse_whenVersionUnknown_thenThrows() {
        #expect(throws: PairingInvitationError.unsupportedVersion(2)) { try PairingInvitation.parse(mutated { $0[0] = 2 }, now: Fixture.now) }
    }

    @Test func parse_whenCutShort_thenThrowsTruncated() {
        #expect(throws: PairingInvitationError.truncated) { try PairingInvitation.parse(mutated { $0.removeLast(20) }, now: Fixture.now) }
        #expect(throws: PairingInvitationError.truncated) { try PairingInvitation.parse(mutated { $0.removeLast(1) }, now: Fixture.now) }
        #expect(throws: PairingInvitationError.truncated) { try PairingInvitation.parse(mutated { $0 = [1] }, now: Fixture.now) }
    }

    @Test func parse_whenExtraBytesFollow_thenThrowsTrailingBytes() {
        #expect(throws: PairingInvitationError.trailingBytes) { try PairingInvitation.parse(mutated { $0.append(0) }, now: Fixture.now) }
    }

    @Test func parse_whenHubNameInvalid_thenThrows() {
        let cases: [(inout [UInt8]) -> Void] = [
            { $0[53] = 0; $0.removeLast(7) },
            { $0[54] = 0xFF },
            { $0[54] = 0x0A },
            { $0[53] = 65; $0.append(contentsOf: [UInt8](repeating: 0x61, count: 58)) },
        ]
        for change in cases {
            #expect(throws: PairingInvitationError.invalidHubName) { try PairingInvitation.parse(mutated(change), now: Fixture.now) }
        }
    }

    @Test func base64URL_whenEncoded_thenUsesURLAlphabetWithoutPadding() {
        let data = Data([0xFB, 0xFF, 0xFE, 0x01])
        let text = Base64URL.encode(data)
        #expect(text == "-__-AQ")
        #expect(Base64URL.decode(text) == data)
    }
}

extension String {
    fileprivate func contains(_ needle: String, after prefix: String) -> Bool {
        dropFirst(prefix.count).contains(needle)
    }
}

@Suite struct PairingSessionTests {
    @Test func open_whenCalled_thenInvitationIsActiveUntilLifetimeEnds() throws {
        var session = PairingSession(lifetime: 60)
        #expect(session.active(at: Fixture.now) == nil)
        #expect(session.secondsRemaining(at: Fixture.now) == 0)
        let invitation = try session.open(hubID: Fixture.hubID, hubName: "Kitchen", profileID: Fixture.profileID, now: Fixture.now, random: FixedRandom(fill: 4))
        #expect(invitation.secret == Fixture.secret(4))
        let active = try #require(session.active(at: Fixture.now.addingTimeInterval(59)))
        #expect(active.invitation == invitation)
        #expect(active.profileID == Fixture.profileID)
        #expect(session.secondsRemaining(at: Fixture.now.addingTimeInterval(0.5)) == 60)
        #expect(session.secondsRemaining(at: Fixture.now.addingTimeInterval(59)) == 1)
        #expect(session.active(at: Fixture.now.addingTimeInterval(60)) == nil)
        #expect(session.secondsRemaining(at: Fixture.now.addingTimeInterval(60)) == 0)
    }

    @Test func close_whenOpen_thenNoInvitation() throws {
        var session = PairingSession()
        try session.open(hubID: Fixture.hubID, hubName: "Kitchen", profileID: nil, now: Fixture.now, random: SystemRandomSource())
        #expect(session.lifetime == PairingSession.defaultLifetime)
        session.close()
        #expect(session.active(at: Fixture.now) == nil)
    }

    @Test func open_whenCalledTwice_thenSecretChanges() throws {
        var session = PairingSession()
        let first = try session.open(hubID: Fixture.hubID, hubName: "K", profileID: nil, now: Fixture.now, random: SystemRandomSource())
        let second = try session.open(hubID: Fixture.hubID, hubName: "K", profileID: nil, now: Fixture.now, random: SystemRandomSource())
        #expect(first.secret != second.secret)
        #expect(session.active(at: Fixture.now)?.invitation == second)
    }
}

@Suite struct PairingStoreTests {
    @Test func saveAndRemove_whenInMemory_thenReflectsChanges() throws {
        let store = InMemoryPairingStore(devices: [Fixture.paired()])
        #expect(try store.devices().map(\.id) == [Fixture.phoneID])
        var other = Fixture.paired(Fixture.otherPhone, fill: 2)
        other.approvedBeamCount = 3
        try store.save(other)
        #expect(try store.devices().count == 2)
        #expect(try store.device(id: Fixture.otherPhoneID)?.approvedBeamCount == 3)
        #expect(try store.device(id: Fixture.hubID) == nil)
        try store.remove(id: Fixture.phoneID)
        #expect(try store.devices().map(\.id) == [Fixture.otherPhoneID])
    }

    @Test func loadOrCreateLocalDeviceID_whenMissing_thenCreatesOnceAndReuses() throws {
        let store = InMemoryPairingStore()
        #expect(try store.localDeviceID() == nil)
        let created = try store.loadOrCreateLocalDeviceID { Fixture.hubID }
        #expect(created == Fixture.hubID)
        #expect(try store.loadOrCreateLocalDeviceID { Fixture.phoneID } == Fixture.hubID)
        #expect(try InMemoryPairingStore(localDeviceID: Fixture.phoneID).loadOrCreateLocalDeviceID() == Fixture.phoneID)
        #expect(try InMemoryPairingStore().loadOrCreateLocalDeviceID() != Fixture.phoneID)
    }

    @Test func calls_whenStoreFails_thenThrowTypedError() {
        let store = InMemoryPairingStore()
        store.failNextCalls(with: .missingEntitlement)
        #expect(throws: PairingStoreError.missingEntitlement) { try store.devices() }
        #expect(throws: PairingStoreError.missingEntitlement) { try store.save(Fixture.paired()) }
        #expect(throws: PairingStoreError.missingEntitlement) { try store.remove(id: Fixture.phoneID) }
        #expect(throws: PairingStoreError.missingEntitlement) { try store.loadOrCreateLocalDeviceID() }
        #expect(throws: PairingStoreError.missingEntitlement) { try store.device(id: Fixture.phoneID) }
        store.failNextCalls(with: .unavailable(-25300))
        #expect(throws: PairingStoreError.unavailable(-25300)) { try store.saveLocalDeviceID(Fixture.hubID) }
        store.failNextCalls(with: nil)
        #expect((try? store.devices()) == [])
    }

    @Test func pairedDevice_whenEncoded_thenRoundTripsWithKeys() throws {
        let record = Fixture.paired(approved: 2)
        let decoded = try JSONDecoder().decode(PairedDevice.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        #expect(decoded.keys == LinkKeys.derive(secret: record.secret, hubID: Fixture.hubID))
        #expect(decoded.id == Fixture.phoneID)
    }
}
