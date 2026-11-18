import Foundation

/// Relayed messages, per household member, held in memory only. Nothing here can be encoded:
/// the inbox stores `RelayedMessage`, whose body is `MemoryOnly`.
public struct MessageInbox: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        public var maxMessagesPerProfile: Int
        public var retention: TimeInterval
        /// The same text from the same correspondent inside this window counts as one message,
        /// because an automation can fire more than once for a single message.
        public var dedupeWindow: TimeInterval

        public init(maxMessagesPerProfile: Int = 200, retention: TimeInterval = 24 * 60 * 60, dedupeWindow: TimeInterval = 5) {
            self.maxMessagesPerProfile = maxMessagesPerProfile
            self.retention = retention
            self.dedupeWindow = dedupeWindow
        }
    }

    public enum InsertOutcome: Sendable, Equatable {
        case inserted
        case duplicate
        /// Older than the retention window on arrival.
        case expired
    }

    public struct Conversation: Sendable, Equatable, Identifiable {
        public let id: String
        /// The correspondent's display name.
        public let title: String
        public let handle: String?
        /// Oldest first.
        public let messages: [RelayedMessage]
        public let unreadCount: Int
        public let lastMessageAt: Date

        /// Text for a list row. `nil` when previews are off, so the row shows the sender only.
        public func preview(showsBody: Bool, limit: Int) -> String? {
            guard showsBody, let last = messages.last else { return nil }
            return last.body.reveal().projectionTruncated(to: limit)
        }
    }

    struct Stored: Sendable, Equatable {
        var message: RelayedMessage
        var isRead: Bool
    }

    private struct Thread {
        var title: String
        var hasIncoming: Bool
        var handle: String?
        var messages: [RelayedMessage]
        var unreadCount: Int
        var lastMessageAt: Date
    }

    public var configuration: Configuration
    private var storage: [UUID: [Stored]] = [:]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Writing

    @discardableResult
    public mutating func insert(_ message: RelayedMessage, for profileID: UUID, now: Date) -> InsertOutcome {
        prune(now: now)
        guard now.timeIntervalSince(message.receivedAt) < configuration.retention else { return .expired }
        var messages = storage[profileID] ?? []
        let isDuplicate = messages.contains { stored in
            stored.message.id == message.id
                || (stored.message.conversationID == message.conversationID
                    && stored.message.direction == message.direction
                    && stored.message.body == message.body
                    && abs(stored.message.receivedAt.timeIntervalSince(message.receivedAt)) <= configuration.dedupeWindow)
        }
        guard !isDuplicate else { return .duplicate }
        messages.append(Stored(message: message, isRead: message.direction == .outgoing))
        messages.sort { $0.message.receivedAt < $1.message.receivedAt }
        if messages.count > configuration.maxMessagesPerProfile {
            messages.removeFirst(messages.count - configuration.maxMessagesPerProfile)
        }
        storage[profileID] = messages
        return .inserted
    }

    /// Drops messages past the retention window. Returns whether anything was removed.
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        var changed = false
        for (profileID, messages) in storage {
            let kept = messages.filter { now.timeIntervalSince($0.message.receivedAt) < configuration.retention }
            if kept.count != messages.count {
                changed = true
                storage[profileID] = kept.isEmpty ? nil : kept
            }
        }
        return changed
    }

    /// Returns whether any message changed from unread to read.
    @discardableResult
    public mutating func markRead(conversationID: String, for profileID: UUID) -> Bool {
        guard var messages = storage[profileID] else { return false }
        var changed = false
        for index in messages.indices where messages[index].message.conversationID == conversationID && !messages[index].isRead {
            messages[index].isRead = true
            changed = true
        }
        storage[profileID] = messages
        return changed
    }

    public mutating func removeAll(for profileID: UUID) {
        storage[profileID] = nil
    }

    public mutating func removeAll() {
        storage.removeAll()
    }

    // MARK: Reading

    public func messageCount(for profileID: UUID) -> Int {
        storage[profileID]?.count ?? 0
    }

    public func unreadCount(for profileID: UUID) -> Int {
        storage[profileID]?.filter { !$0.isRead }.count ?? 0
    }

    /// Newest conversation first.
    public func conversations(for profileID: UUID) -> [Conversation] {
        var threads: [String: Thread] = [:]
        for stored in storage[profileID] ?? [] {
            let message = stored.message
            var thread = threads[message.conversationID] ?? Thread(
                title: message.senderName,
                hasIncoming: false,
                handle: nil,
                messages: [],
                unreadCount: 0,
                lastMessageAt: message.receivedAt
            )
            // The title is the correspondent, so a reply does not rename a thread that has incoming messages.
            if message.direction == .incoming || !thread.hasIncoming {
                thread.title = message.senderName
            }
            thread.hasIncoming = thread.hasIncoming || message.direction == .incoming
            thread.handle = message.handle ?? thread.handle
            thread.messages.append(message)
            thread.unreadCount += stored.isRead ? 0 : 1
            thread.lastMessageAt = message.receivedAt
            threads[message.conversationID] = thread
        }
        return threads.map { conversationID, thread in
            Conversation(
                id: conversationID,
                title: thread.title,
                handle: thread.handle,
                messages: thread.messages,
                unreadCount: thread.unreadCount,
                lastMessageAt: thread.lastMessageAt
            )
        }
        .sorted { ($0.lastMessageAt, $0.id) > ($1.lastMessageAt, $1.id) }
    }

    public func conversation(id: String, for profileID: UUID) -> Conversation? {
        conversations(for: profileID).first { $0.id == id }
    }
}
