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

    @Test func mirror_whenContainerIsDumped_thenBodyIsNotShown() {
        let message = Fixture.message("the secret body")
        var output = ""
        dump(message, to: &output)
        #expect(!output.contains("secret"))
        #expect(!"\(message)".contains("secret"))
    }

    @Test func mutate_whenBodyChangesValue_thenValueIsUpdated() {
        var wrapped = MemoryOnly([1])
        wrapped.mutate { $0.append(2) }
        #expect(wrapped.reveal() == [1, 2])
        #expect(wrapped == MemoryOnly([1, 2]))
    }
}
