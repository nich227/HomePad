import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct FaceTemplateStoreTests {
    private let alice = UUID()
    private let bob = UUID()

    @Test func save_whenProfileAlreadyStored_thenReplacesIt() throws {
        let store = InMemoryFaceTemplateStore(templates: [try template(alice, degrees: [0])])
        let replacement = try template(alice, degrees: [45])
        try store.save(replacement)
        try store.save(try template(bob, degrees: [90]))
        let all = try store.loadAll()
        #expect(all.count == 2)
        #expect(all.first { $0.profileID == alice } == replacement)
    }

    @Test func init_whenTwoTemplatesShareAProfile_thenKeepsTheLaterOne() throws {
        let later = try template(alice, degrees: [45])
        let store = InMemoryFaceTemplateStore(templates: [try template(alice, degrees: [0]), later])
        #expect(try store.loadAll() == [later])
    }

    @Test func delete_whenProfileStored_thenOnlyThatTemplateGoes() throws {
        let store = InMemoryFaceTemplateStore(templates: [try template(alice, degrees: [0]), try template(bob, degrees: [90])])
        try store.delete(profileID: alice)
        try store.delete(profileID: UUID())
        #expect(try store.loadAll().map(\.profileID) == [bob])
    }

    @Test func deleteAll_whenTemplatesStored_thenStoreIsEmpty() throws {
        let store = InMemoryFaceTemplateStore(templates: [try template(alice, degrees: [0]), try template(bob, degrees: [90])])
        try store.deleteAll()
        #expect(try store.loadAll().isEmpty)
    }

    @Test func everyCall_whenStoreIsFailing_thenThrowsTheInjectedError() throws {
        let store = InMemoryFaceTemplateStore()
        let failure = FaceTemplateStoreError.keychain(status: -25300)
        store.failNextCalls(with: failure)
        #expect(throws: failure) { try store.loadAll() }
        #expect(throws: failure) { try store.save(try template(alice, degrees: [0])) }
        #expect(throws: failure) { try store.delete(profileID: alice) }
        #expect(throws: failure) { try store.deleteAll() }
        #expect(throws: failure) { try store.deleteOrphans(keeping: []) }
        store.failNextCalls(with: nil)
        #expect(try store.loadAll().isEmpty)
    }

    @Test func deleteOrphans_whenMemberNoLongerExists_thenDeletesOnlyTheirTemplate() throws {
        let store = InMemoryFaceTemplateStore(templates: [try template(alice, degrees: [0]), try template(bob, degrees: [90])])
        #expect(try store.deleteOrphans(keeping: [alice]) == [bob])
        #expect(try store.loadAll().map(\.profileID) == [alice])
        #expect(try store.deleteOrphans(keeping: [alice]).isEmpty)
    }
}

@Suite struct FaceTemplateEnvelopeTests {
    private let alice = UUID()

    @Test func encoded_whenDecoded_thenEqual() throws {
        let envelope = FaceTemplateEnvelope(template: try template(alice, degrees: [0, 20]))
        #expect(envelope.formatVersion == FaceTemplateEnvelope.currentFormatVersion)
        #expect(try FaceTemplateEnvelope.decode(envelope.encoded()) == envelope)
    }

    @Test func encoded_whenTemplateCannotBeWrittenAsJSON_thenThrowsEncodingFailed() throws {
        let unwritable = try FaceTemplate(
            profileID: alice,
            samples: [FaceTemplate.Sample(bucket: .center, embedding: try vector(0))],
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )
        #expect(throws: FaceTemplateStoreError.encodingFailed) { try FaceTemplateEnvelope(template: unwritable).encoded() }
    }

    @Test func decode_whenDataIsNotAnEnvelope_thenThrowsCorruptedTemplate() {
        #expect(throws: FaceTemplateStoreError.corruptedTemplate) { try FaceTemplateEnvelope.decode(Data("not json".utf8)) }
    }

    @Test func decode_whenFormatVersionUnknown_thenThrowsUnsupportedFormat() {
        #expect(throws: FaceTemplateStoreError.unsupportedFormat(7)) {
            try FaceTemplateEnvelope.decode(Data(#"{"formatVersion":7,"template":{}}"#.utf8))
        }
    }

    @Test func decode_whenTemplateIsDamaged_thenThrowsCorruptedTemplate() {
        #expect(throws: FaceTemplateStoreError.corruptedTemplate) {
            try FaceTemplateEnvelope.decode(Data(#"{"formatVersion":1,"template":{"version":1}}"#.utf8))
        }
    }

    @Test func account_whenRoundTripped_thenReturnsProfileID() {
        let account = FaceTemplateEnvelope.account(for: alice)
        #expect(account == "face-template." + alice.uuidString)
        #expect(FaceTemplateEnvelope.profileID(fromAccount: account) == alice)
    }

    @Test func profileID_whenAccountBelongsToSomethingElse_thenNil() {
        #expect(FaceTemplateEnvelope.profileID(fromAccount: "pairing-key." + alice.uuidString) == nil)
        #expect(FaceTemplateEnvelope.profileID(fromAccount: "face-template.not-a-uuid") == nil)
    }
}
