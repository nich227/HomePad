import Foundation
import HomePadCore
import HomePadMessagingCore
import Observation
import UIKit

/// A reply typed on the hub, waiting on the companion for its owner to send it.
public struct PendingReply: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let conversationID: String
    public let recipientName: String
    /// Phone number or email, when the relay supplied one.
    public let recipientHandle: String?
    public let text: MemoryOnly<String>
    public let requestedAt: Date
}

/// The Messages app a companion projects. It holds only what Shortcuts relayed to it while the app
/// has been running; it cannot read the Messages database.
@MainActor
@Observable
public final class MessagesAppProvider: ProjectedAppProvider {
    public let app = ProjectedApp(
        id: BuiltInProjectedApp.messagesID,
        name: String(localized: "Messages"),
        symbolName: "message.fill",
        tint: .green,
        category: .communication,
        requiresPersonalContent: true
    )
    public let rootTemplateID = MessagesProjection.rootTemplateID

    /// Replies waiting for the owner, oldest first.
    public private(set) var pendingReplies: [PendingReply] = []

    @ObservationIgnored private var inbox: MessageInbox
    @ObservationIgnored private var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let ownerID: UUID
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let notifier: any HomePadNotifying
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(
        ownerID: UUID,
        settings: HomePadSettings,
        notifier: any HomePadNotifying,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ownerID = ownerID
        self.settings = settings
        self.notifier = notifier
        self.now = now
        self.inbox = MessageInbox()
    }

    public var pendingReply: PendingReply? { pendingReplies.first }

    // MARK: Provider

    public func activate(onChange: @escaping @MainActor () -> Void) async {
        self.onChange = onChange
    }

    public func deactivate() {
        onChange = nil
        // Turning Messages projection off in Settings also forgets what was relayed.
        inbox.removeAll()
        pendingReplies.removeAll()
    }

    public func template(id: String) async -> ProjectionTemplate? {
        applyRetention()
        if id == rootTemplateID {
            return MessagesProjection.listTemplate(
                conversations: inbox.conversations(for: ownerID),
                title: app.name,
                emptyMessage: String(localized: "No messages have been relayed yet."),
                showsPreviews: settings[MessagingSettings.showMessagePreviews]
            )
        }
        guard let conversationID = MessagesProjection.conversationID(fromTemplateID: id),
              let conversation = inbox.conversation(id: conversationID, for: ownerID)
        else { return nil }
        return MessagesProjection.conversationTemplate(conversation, canReply: true)
    }

    public func handle(actionID: String, payload: [String: String]) async -> ProjectionNavigation {
        guard let conversationID = MessagesProjection.conversationID(fromActionID: actionID),
              inbox.conversation(id: conversationID, for: ownerID) != nil
        else { return .none }
        if inbox.markRead(conversationID: conversationID, for: ownerID) {
            onChange?()
        }
        return .showDetail(templateID: MessagesProjection.conversationTemplateID(conversationID: conversationID))
    }

    // MARK: Relay

    /// Stores a message that a Shortcuts automation handed over.
    func receive(senderName: String, handle: String?, text: String) -> Result<MessageInbox.InsertOutcome, RelayedMessageError> {
        applyRetention()
        do {
            let message = try RelayedMessage(id: UUID(), senderName: senderName, handle: handle, text: text, receivedAt: now())
            return .success(inbox.insert(message, for: ownerID, now: now()))
        } catch {
            return .failure(error)
        }
    }

    // MARK: Replies

    /// Queues a reply from the hub. Nothing is sent here: the owner reviews it in the system
    /// message sheet and taps Send.
    func queueReply(conversationID: String, text: MemoryOnly<String>) async {
        guard let conversation = inbox.conversation(id: conversationID, for: ownerID) else { return }
        let reply = PendingReply(
            id: UUID(),
            conversationID: conversationID,
            recipientName: conversation.title,
            recipientHandle: conversation.handle,
            text: text,
            requestedAt: now()
        )
        pendingReplies.append(reply)
        if UIApplication.shared.applicationState != .active {
            await notifier.postPendingReply(recipientName: reply.recipientName, identifier: reply.id.uuidString)
        }
    }

    /// Call when the message sheet finishes. A sent reply joins the conversation shown on the hub.
    public func finish(_ reply: PendingReply, sent: Bool) {
        pendingReplies.removeAll { $0.id == reply.id }
        notifier.removeDelivered(identifier: reply.id.uuidString)
        guard sent,
              let message = try? RelayedMessage(
                  id: reply.id,
                  senderName: reply.recipientName,
                  handle: reply.recipientHandle,
                  text: reply.text.reveal(),
                  receivedAt: now(),
                  direction: .outgoing,
                  conversationID: reply.conversationID
              )
        else { return }
        inbox.insert(message, for: ownerID, now: now())
        onChange?()
    }

    private func applyRetention() {
        inbox.configuration.retention = MessagingSettings.retention(hours: settings[MessagingSettings.retentionHours])
        inbox.prune(now: now())
    }
}
