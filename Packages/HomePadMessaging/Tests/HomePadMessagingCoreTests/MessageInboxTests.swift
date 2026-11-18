import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct RelayedMessageTests {
    @Test func init_whenInputHasPadding_thenTrimsAndKeepsFields() throws {
        let id = UUID()
        let message = try RelayedMessage(id: id, senderName: "  Carol ", handle: " +15550100000 ", text: "\nHello\n", receivedAt: Fixture.t0)
        #expect(message.id == id)
        #expect(message.senderName == "Carol")
        #expect(message.handle == "+15550100000")
        #expect(message.body.reveal() == "Hello")
        #expect(message.direction == .incoming)
        #expect(message.receivedAt == Fixture.t0)
    }

    @Test func init_whenSenderOrBodyBlank_thenThrows() {
        #expect(throws: RelayedMessageError.emptySender) { _ = try RelayedMessage(id: UUID(), senderName: "  ", text: "Hi", receivedAt: Fixture.t0) }
        #expect(throws: RelayedMessageError.emptyBody) { _ = try RelayedMessage(id: UUID(), senderName: "Carol", text: " \n", receivedAt: Fixture.t0) }
    }

    @Test func init_whenHandleBlank_thenHandleIsNil() throws {
        #expect(try RelayedMessage(id: UUID(), senderName: "Carol", handle: "  ", text: "Hi", receivedAt: Fixture.t0).handle == nil)
    }

    @Test func init_whenTextExceedsLimits_thenTruncated() throws {
        let message = try RelayedMessage(
            id: UUID(),
            senderName: String(repeating: "s", count: 200),
            handle: String(repeating: "9", count: 300),
            text: String(repeating: "b", count: 5000),
            receivedAt: Fixture.t0
        )
        #expect(message.senderName.count == 80)
        #expect(message.handle?.count == 128)
        #expect(message.body.reveal().count == 2000)
    }

    @Test func init_whenConversationIDGiven_thenUsesItInsteadOfDerivingOne() throws {
        let reply = try RelayedMessage(id: UUID(), senderName: "Carol", text: "Hi", receivedAt: Fixture.t0, direction: .outgoing, conversationID: "thread-1")
        #expect(reply.conversationID == "thread-1")
        #expect(reply.direction == .outgoing)
    }

    @Test func conversationID_whenHandleFormattingDiffers_thenSameConversation() {
        let a = RelayedMessage.conversationID(senderName: "Carol", handle: "+1 (555) 010-0000")
        let b = RelayedMessage.conversationID(senderName: "Carol Smith", handle: "+15550100000")
        #expect(a == b)
        #expect(a.count == 24)
    }

    @Test func conversationID_whenNoHandle_thenDerivedFromNameIgnoringCase() {
        #expect(RelayedMessage.conversationID(senderName: " carol ", handle: nil) == RelayedMessage.conversationID(senderName: "Carol", handle: nil))
        #expect(RelayedMessage.conversationID(senderName: "Carol", handle: nil) != RelayedMessage.conversationID(senderName: "Dave", handle: nil))
        #expect(RelayedMessage.conversationID(senderName: "Carol", handle: nil) != RelayedMessage.conversationID(senderName: "Carol", handle: "carol"))
    }

    @Test func conversationID_whenDerived_thenDoesNotContainTheNameOrNumber() {
        let id = RelayedMessage.conversationID(senderName: "Carol", handle: "+15550100000")
        #expect(!id.lowercased().contains("carol"))
        #expect(!id.contains("5550100000"))
    }
}

@Suite struct MessageInboxTests {
    private let profile = Fixture.alice

    @Test func insert_whenNew_thenStoredUnread() {
        var inbox = MessageInbox()
        #expect(evaluated { inbox.insert(Fixture.message(), for: profile, now: Fixture.t0) } == .inserted)
        #expect(inbox.messageCount(for: profile) == 1)
        #expect(inbox.unreadCount(for: profile) == 1)
        #expect(inbox.unreadCount(for: Fixture.bob) == 0)
    }

    @Test func insert_whenSameIDTwice_thenDuplicate() {
        var inbox = MessageInbox()
        let message = Fixture.message()
        inbox.insert(message, for: profile, now: Fixture.t0)
        #expect(evaluated { inbox.insert(message, for: profile, now: Fixture.t0) } == .duplicate)
        #expect(inbox.messageCount(for: profile) == 1)
    }

    @Test func insert_whenSameTextFromSameSenderInsideWindow_thenDuplicate() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("Hi", at: Fixture.t0), for: profile, now: Fixture.t0)
        #expect(evaluated { inbox.insert(Fixture.message("Hi", at: Fixture.t0.addingTimeInterval(5)), for: profile, now: Fixture.t0.addingTimeInterval(5)) } == .duplicate)
    }

    @Test func insert_whenSameTextOutsideWindowOrDifferentSenderOrDirection_thenInserted() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("Hi", at: Fixture.t0), for: profile, now: Fixture.t0)
        #expect(evaluated { inbox.insert(Fixture.message("Hi", at: Fixture.t0.addingTimeInterval(6)), for: profile, now: Fixture.t0.addingTimeInterval(6)) } == .inserted)
        #expect(evaluated { inbox.insert(Fixture.message("Hi", from: "Dave", handle: nil, at: Fixture.t0), for: profile, now: Fixture.t0.addingTimeInterval(6)) } == .inserted)
        #expect(evaluated { inbox.insert(Fixture.message("Hi", at: Fixture.t0, direction: .outgoing), for: profile, now: Fixture.t0.addingTimeInterval(6)) } == .inserted)
        #expect(inbox.messageCount(for: profile) == 4)
    }

    @Test func insert_whenOlderThanRetention_thenExpired() {
        var inbox = MessageInbox(configuration: .init(retention: 60))
        #expect(evaluated { inbox.insert(Fixture.message(at: Fixture.t0), for: profile, now: Fixture.t0.addingTimeInterval(60)) } == .expired)
        #expect(inbox.messageCount(for: profile) == 0)
    }

    @Test func insert_whenOverCap_thenOldestAreDropped() {
        var inbox = MessageInbox(configuration: .init(maxMessagesPerProfile: 3))
        for index in 0..<5 {
            inbox.insert(Fixture.message("m\(index)", at: Fixture.t0.addingTimeInterval(Double(index) * 10)), for: profile, now: Fixture.t0.addingTimeInterval(50))
        }
        let texts = inbox.conversations(for: profile).flatMap(\.messages).map { $0.body.reveal() }
        #expect(texts == ["m2", "m3", "m4"])
    }

    @Test func insert_whenArrivingOutOfOrder_thenStoredChronologically() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("second", at: Fixture.t0.addingTimeInterval(20)), for: profile, now: Fixture.t0.addingTimeInterval(30))
        inbox.insert(Fixture.message("first", at: Fixture.t0), for: profile, now: Fixture.t0.addingTimeInterval(30))
        #expect(inbox.conversations(for: profile)[0].messages.map { $0.body.reveal() } == ["first", "second"])
    }

    @Test func insert_whenOutgoing_thenCountsAsRead() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message(direction: .outgoing), for: profile, now: Fixture.t0)
        #expect(inbox.unreadCount(for: profile) == 0)
    }

    @Test func insert_whenDifferentProfiles_thenInboxesAreSeparate() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("for alice"), for: Fixture.alice, now: Fixture.t0)
        inbox.insert(Fixture.message("for bob"), for: Fixture.bob, now: Fixture.t0)
        #expect(inbox.conversations(for: Fixture.alice).flatMap(\.messages).map { $0.body.reveal() } == ["for alice"])
        #expect(inbox.conversations(for: Fixture.bob).flatMap(\.messages).map { $0.body.reveal() } == ["for bob"])
        inbox.removeAll(for: Fixture.alice)
        #expect(inbox.messageCount(for: Fixture.alice) == 0)
        #expect(inbox.messageCount(for: Fixture.bob) == 1)
        inbox.removeAll()
        #expect(inbox.messageCount(for: Fixture.bob) == 0)
    }

    @Test func prune_whenMessagesPassRetention_thenRemovedAndReported() {
        var inbox = MessageInbox(configuration: .init(retention: 100))
        inbox.insert(Fixture.message("old", at: Fixture.t0), for: profile, now: Fixture.t0)
        inbox.insert(Fixture.message("new", at: Fixture.t0.addingTimeInterval(90)), for: profile, now: Fixture.t0.addingTimeInterval(90))
        #expect(evaluated { inbox.prune(now: Fixture.t0.addingTimeInterval(99)) } == false)
        #expect(evaluated { inbox.prune(now: Fixture.t0.addingTimeInterval(100)) } == true)
        #expect(inbox.conversations(for: profile).flatMap(\.messages).map { $0.body.reveal() } == ["new"])
        #expect(evaluated { inbox.prune(now: Fixture.t0.addingTimeInterval(1000)) } == true)
        #expect(inbox.conversations(for: profile).isEmpty)
    }

    @Test func prune_whenRetentionIsShortenedInConfiguration_thenAppliesOnNextPrune() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message(at: Fixture.t0), for: profile, now: Fixture.t0)
        inbox.configuration.retention = 3600
        #expect(evaluated { inbox.prune(now: Fixture.t0.addingTimeInterval(3600)) } == true)
    }

    @Test func markRead_whenConversationHasUnread_thenClearsOnlyThatConversation() {
        var inbox = MessageInbox()
        let carol = Fixture.message("a", from: "Carol")
        inbox.insert(carol, for: profile, now: Fixture.t0)
        inbox.insert(Fixture.message("b", from: "Dave", handle: nil), for: profile, now: Fixture.t0)
        #expect(evaluated { inbox.markRead(conversationID: carol.conversationID, for: profile) } == true)
        #expect(inbox.unreadCount(for: profile) == 1)
        #expect(evaluated { inbox.markRead(conversationID: carol.conversationID, for: profile) } == false)
        #expect(evaluated { inbox.markRead(conversationID: carol.conversationID, for: Fixture.bob) } == false)
    }

    @Test func conversations_whenSeveralSenders_thenGroupedNewestFirstWithCounts() throws {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("c1", from: "Carol", at: Fixture.t0), for: profile, now: Fixture.t0)
        inbox.insert(Fixture.message("d1", from: "Dave", handle: nil, at: Fixture.t0.addingTimeInterval(10)), for: profile, now: Fixture.t0.addingTimeInterval(10))
        inbox.insert(Fixture.message("c2", from: "Carol", at: Fixture.t0.addingTimeInterval(20)), for: profile, now: Fixture.t0.addingTimeInterval(20))
        let conversations = inbox.conversations(for: profile)
        #expect(conversations.map(\.title) == ["Carol", "Dave"])
        #expect(conversations[0].messages.map { $0.body.reveal() } == ["c1", "c2"])
        #expect(conversations[0].unreadCount == 2)
        #expect(conversations[0].lastMessageAt == Fixture.t0.addingTimeInterval(20))
        #expect(conversations[0].handle == "+1 (555) 010-0000")
        #expect(conversations[1].handle == nil)
        let found = try #require(inbox.conversation(id: conversations[1].id, for: profile))
        #expect(found.title == "Dave")
        #expect(inbox.conversation(id: "missing", for: profile) == nil)
    }

    @Test func conversations_whenLastMessageIsAReply_thenTitleIsStillTheCorrespondent() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("hi", from: "Carol", at: Fixture.t0), for: profile, now: Fixture.t0)
        inbox.insert(Fixture.message("hello back", from: "Carol", at: Fixture.t0.addingTimeInterval(5), direction: .outgoing), for: profile, now: Fixture.t0.addingTimeInterval(5))
        let conversation = inbox.conversations(for: profile)[0]
        #expect(conversation.title == "Carol")
        #expect(conversation.messages.count == 2)
        #expect(conversation.unreadCount == 1)
    }

    @Test func conversations_whenOnlyAReplyExists_thenTitleFallsBackToItsRecipientName() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("hello", from: "Carol", direction: .outgoing), for: profile, now: Fixture.t0)
        #expect(inbox.conversations(for: profile).map(\.title) == ["Carol"])
    }

    @Test func preview_whenPreviewsAreOff_thenNil() {
        var inbox = MessageInbox()
        inbox.insert(Fixture.message("the secret"), for: profile, now: Fixture.t0)
        let conversation = inbox.conversations(for: profile)[0]
        #expect(conversation.preview(showsBody: false, limit: 160) == nil)
        #expect(conversation.preview(showsBody: true, limit: 160) == "the secret")
        #expect(conversation.preview(showsBody: true, limit: 4) == "the\u{2026}")
    }

    @Test func preview_whenConversationHasNoMessages_thenNil() {
        let empty = MessageInbox.Conversation(id: "c", title: "Carol", handle: nil, messages: [], unreadCount: 0, lastMessageAt: Fixture.t0)
        #expect(empty.preview(showsBody: true, limit: 10) == nil)
    }
}
