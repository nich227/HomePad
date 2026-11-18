import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct HouseholdNoteTests {
    private func note(_ text: String = "Dinner is ready", id: UUID = UUID()) -> HouseholdNote {
        HouseholdNote(id: id, senderName: "Alice", senderProfileID: Fixture.alice, text: text, sentAt: Fixture.t0)
    }

    @Test func make_whenValid_thenTrimsFields() throws {
        let id = UUID()
        let made = try HouseholdNoteCodec.make(id: id, senderName: " Kitchen ", senderProfileID: nil, text: "\nDinner\n", sentAt: Fixture.t0)
        #expect(made == HouseholdNote(version: 1, id: id, senderName: "Kitchen", senderProfileID: nil, text: "Dinner", sentAt: Fixture.t0))
    }

    @Test func make_whenInvalid_thenThrows() {
        #expect(throws: HouseholdNoteError.emptyText) { _ = try HouseholdNoteCodec.make(id: UUID(), senderName: "A", senderProfileID: nil, text: "  ", sentAt: Fixture.t0) }
        #expect(throws: HouseholdNoteError.emptySender) { _ = try HouseholdNoteCodec.make(id: UUID(), senderName: " ", senderProfileID: nil, text: "Hi", sentAt: Fixture.t0) }
        #expect(throws: HouseholdNoteError.emptySender) {
            _ = try HouseholdNoteCodec.make(id: UUID(), senderName: String(repeating: "s", count: 81), senderProfileID: nil, text: "Hi", sentAt: Fixture.t0)
        }
        #expect(throws: HouseholdNoteError.textTooLong(limit: 280)) {
            _ = try HouseholdNoteCodec.make(id: UUID(), senderName: "A", senderProfileID: nil, text: String(repeating: "t", count: 281), sentAt: Fixture.t0)
        }
    }

    @Test func codec_whenEncodedAndDecoded_thenRoundTrips() throws {
        let original = note()
        #expect(try HouseholdNoteCodec.decode(HouseholdNoteCodec.encode(original)) == original)
    }

    @Test func encode_whenNoteInvalid_thenThrows() {
        #expect(throws: HouseholdNoteError.emptyText) { _ = try HouseholdNoteCodec.encode(note("")) }
        let future = HouseholdNote(version: 2, id: UUID(), senderName: "A", senderProfileID: nil, text: "Hi", sentAt: Fixture.t0)
        #expect(throws: HouseholdNoteError.unsupportedVersion(2)) { _ = try HouseholdNoteCodec.encode(future) }
    }

    @Test func decode_whenVersionIsNewer_thenFailsClosed() throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "payload": "new shape"])
        #expect(throws: HouseholdNoteError.unsupportedVersion(2)) { _ = try HouseholdNoteCodec.decode(data) }
    }

    @Test func decode_whenMalformedOrOversized_thenThrows() throws {
        #expect(throws: HouseholdNoteError.malformed) { _ = try HouseholdNoteCodec.decode(Data("nope".utf8)) }
        #expect(throws: HouseholdNoteError.malformed) { _ = try HouseholdNoteCodec.decode(JSONSerialization.data(withJSONObject: ["version": 1])) }
        #expect(throws: HouseholdNoteError.malformed) { _ = try HouseholdNoteCodec.decode(Data(count: HouseholdNoteCodec.maxPayloadBytes + 1)) }
    }

    @Test func decode_whenContentBreaksLimits_thenThrows() throws {
        let long = HouseholdNote(id: UUID(), senderName: "A", senderProfileID: nil, text: String(repeating: "t", count: 281), sentAt: Fixture.t0)
        let data = try JSONEncoder().encode(long)
        #expect(throws: HouseholdNoteError.textTooLong(limit: 280)) { _ = try HouseholdNoteCodec.decode(data) }
    }
}

@Suite struct NoteBannerQueueTests {
    private func note(_ text: String) -> HouseholdNote {
        HouseholdNote(id: UUID(), senderName: "Alice", senderProfileID: nil, text: text, sentAt: Fixture.t0)
    }

    @Test func enqueue_whenFirstNote_thenShownImmediately() {
        var queue = NoteBannerQueue()
        let first = note("one")
        #expect(evaluated { queue.enqueue(first, now: Fixture.t0) })
        #expect(evaluated { queue.current(now: Fixture.t0) } == first)
        #expect(queue.pendingCount == 0)
    }

    @Test func enqueue_whenSameNoteArrivesTwice_thenIgnored() {
        var queue = NoteBannerQueue()
        let first = note("one")
        queue.enqueue(first, now: Fixture.t0)
        #expect(!evaluated { queue.enqueue(first, now: Fixture.t0) })
        queue.dismissCurrent(now: Fixture.t0)
        #expect(!evaluated { queue.enqueue(first, now: Fixture.t0) })
        #expect(evaluated { queue.current(now: Fixture.t0) } == nil)
    }

    @Test func current_whenDisplayDurationPasses_thenAdvancesToNextThenEmpties() {
        var queue = NoteBannerQueue(displayDuration: 10)
        let first = note("one"), second = note("two")
        queue.enqueue(first, now: Fixture.t0)
        queue.enqueue(second, now: Fixture.t0.addingTimeInterval(1))
        #expect(evaluated { queue.current(now: Fixture.t0.addingTimeInterval(9)) } == first)
        #expect(evaluated { queue.current(now: Fixture.t0.addingTimeInterval(10)) } == second)
        #expect(evaluated { queue.current(now: Fixture.t0.addingTimeInterval(19)) } == second)
        #expect(evaluated { queue.current(now: Fixture.t0.addingTimeInterval(20)) } == nil)
    }

    @Test func dismissCurrent_whenAnotherIsPending_thenShowsIt() {
        var queue = NoteBannerQueue()
        let first = note("one"), second = note("two")
        queue.enqueue(first, now: Fixture.t0)
        queue.enqueue(second, now: Fixture.t0)
        queue.dismissCurrent(now: Fixture.t0)
        #expect(evaluated { queue.current(now: Fixture.t0) } == second)
    }

    @Test func enqueue_whenOverCapacity_thenOldestPendingAreDropped() {
        var queue = NoteBannerQueue(displayDuration: 10, capacity: 2)
        let notes = (0..<5).map { note("n\($0)") }
        for item in notes {
            queue.enqueue(item, now: Fixture.t0)
        }
        #expect(evaluated { queue.current(now: Fixture.t0) } == notes[0])
        #expect(queue.pendingCount == 2)
        queue.dismissCurrent(now: Fixture.t0)
        #expect(evaluated { queue.current(now: Fixture.t0) } == notes[3])
    }

    @Test func enqueue_whenManyNotesHavePassed_thenOldIDsAreForgotten() {
        var queue = NoteBannerQueue(displayDuration: 10, capacity: 1)
        let first = note("first")
        queue.enqueue(first, now: Fixture.t0)
        for index in 0..<4 {
            queue.enqueue(note("n\(index)"), now: Fixture.t0)
        }
        #expect(evaluated { queue.enqueue(first, now: Fixture.t0) })
    }
}
