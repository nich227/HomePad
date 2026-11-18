import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct MemoryOnlyTests {
    @Test func reveal_whenWrapped_thenReturnsContent() {
        #expect(MemoryOnly("secret").reveal() == "secret")
    }

    @Test func description_whenPrintedOrInterpolated_thenContentIsNotShown() {
        let wrapped = MemoryOnly("secret body")
        #expect("\(wrapped)" == MemoryOnly<String>.placeholder)
        #expect(String(describing: wrapped) == MemoryOnly<String>.placeholder)
        #expect(String(reflecting: wrapped) == MemoryOnly<String>.placeholder)
    }

    @Test func mirror_whenDumped_thenContentIsNotShown() {
        let wrapped = MemoryOnly("secret body")
        var output = ""
        dump(wrapped, to: &output)
        #expect(!output.contains("secret"))
        #expect(Mirror(reflecting: wrapped).children.isEmpty)
    }

    @Test func mirror_whenContainerIsDumped_thenContentIsNotShown() throws {
        var state = ProjectionClientState(session: Fixture.hubSession)
        try state.apply(Fixture.hostFrame(.announce([Fixture.app()]), sequence: 1), from: Fixture.phone, now: Fixture.t0)
        try state.apply(Fixture.hostFrame(.setRoot(appID: "calendar", template: Fixture.list(title: "the secret title")), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        var output = ""
        dump(state, to: &output)
        #expect(!output.contains("secret"))
        #expect(!"\(state)".contains("secret"))
        let entry = ProjectedAppEntryID(deviceID: Fixture.phoneID, appID: "calendar")
        #expect(state.content(for: entry, viewer: Fixture.aliceVerified) == .template(Fixture.list(title: "the secret title"), receivedAt: Fixture.t0, depth: 1))
    }

    @Test func mutate_whenBodyChangesValue_thenValueIsUpdated() {
        var wrapped = MemoryOnly([1])
        wrapped.mutate { $0.append(2) }
        #expect(wrapped.reveal() == [1, 2])
        #expect(wrapped == MemoryOnly([1, 2]))
    }
}
