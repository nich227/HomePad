import Foundation
import HomePadCore

public enum BuiltInProjectedApp {
    public static let messagesID = "messages"
    public static let calendarID = "calendar"
    public static let remindersID = "reminders"
    public static let nowPlayingID = "nowPlaying"
}

/// Builds the Messages app's templates from the inbox.
public enum MessagesProjection {
    public static let rootTemplateID = "messages.list"
    private static let conversationPrefix = "messages.conversation."
    private static let openPrefix = "messages.open."

    public static func conversationTemplateID(conversationID: String) -> String {
        conversationPrefix + conversationID
    }

    public static func conversationID(fromTemplateID templateID: String) -> String? {
        suffix(of: templateID, after: conversationPrefix)
    }

    public static func openActionID(conversationID: String) -> String {
        openPrefix + conversationID
    }

    public static func conversationID(fromActionID actionID: String) -> String? {
        suffix(of: actionID, after: openPrefix)
    }

    private static func suffix(of value: String, after prefix: String) -> String? {
        guard value.hasPrefix(prefix), value.count > prefix.count else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    public static func listTemplate(
        conversations: [MessageInbox.Conversation],
        title: String,
        emptyMessage: String,
        showsPreviews: Bool,
        limits: ProjectionLimits = .standard
    ) -> ProjectionTemplate {
        let summaries = conversations.prefix(limits.maxConversations).map { conversation in
            ProjectedConversationSummary(
                id: conversation.id,
                title: conversation.title,
                preview: conversation.preview(showsBody: showsPreviews, limit: limits.maxSubtitleLength),
                lastMessageAt: conversation.lastMessageAt,
                unreadCount: conversation.unreadCount,
                actionID: openActionID(conversationID: conversation.id)
            )
        }
        return .conversationList(
            ConversationListTemplate(
                id: rootTemplateID,
                title: title.projectionTruncated(to: limits.maxTitleLength),
                conversations: Array(summaries),
                emptyMessage: emptyMessage.projectionTruncated(to: limits.maxSubtitleLength)
            )
        )
    }

    /// The newest messages of one conversation, oldest first.
    public static func conversationTemplate(
        _ conversation: MessageInbox.Conversation,
        canReply: Bool,
        limits: ProjectionLimits = .standard
    ) -> ProjectionTemplate {
        let bubbles = conversation.messages.suffix(limits.maxBubbles).map { message in
            ProjectedBubble(
                id: message.id.uuidString,
                text: message.body.reveal(),
                isFromMe: message.direction == .outgoing,
                sentAt: message.receivedAt
            )
        }
        return .conversation(
            ConversationTemplate(
                id: conversationTemplateID(conversationID: conversation.id),
                title: conversation.title,
                conversationID: conversation.id,
                recipientHandle: conversation.handle,
                bubbles: Array(bubbles),
                canReply: canReply
            )
        )
    }
}

/// An event or reminder as the companion read it, before it is laid out for the hub.
public struct AgendaItem: Sendable, Equatable {
    public var id: String
    public var kind: AgendaEntryKind
    public var title: String
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    public var detail: String?
    public var isCompleted: Bool

    public init(
        id: String,
        kind: AgendaEntryKind,
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        detail: String? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.detail = detail
        self.isCompleted = isCompleted
    }
}

public enum AgendaProjection {
    private static let togglePrefix = "agenda.toggle."

    public static func toggleActionID(itemID: String) -> String {
        togglePrefix + itemID
    }

    public static func itemID(fromToggleActionID actionID: String) -> String? {
        guard actionID.hasPrefix(togglePrefix), actionID.count > togglePrefix.count else { return nil }
        return String(actionID.dropFirst(togglePrefix.count))
    }

    /// Orders items by start time with undated ones last, drops events that have ended and items
    /// with unusable ids, and trims everything to the limits. Reminders get a toggle action.
    public static func template(
        id: String,
        title: String,
        emptyMessage: String,
        items: [AgendaItem],
        untitled: String,
        now: Date,
        limits: ProjectionLimits = .standard
    ) -> ProjectionTemplate {
        let validator = ProjectionValidator(limits: limits)
        let upcoming = items.filter { item in
            guard validator.isUsableIdentifier(item.id), validator.isUsableIdentifier(toggleActionID(itemID: item.id)) else { return false }
            guard item.kind == .event, let end = item.end else { return true }
            return end > now
        }
        var seen: Set<String> = []
        let unique = upcoming.filter { seen.insert($0.id).inserted }
        let sorted = unique.sorted { first, second in
            switch (first.start, second.start) {
            case let (a?, b?): a == b ? first.title < second.title : a < b
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): first.title < second.title
            }
        }
        let entries = sorted.prefix(limits.maxAgendaEntries).map { item in
            let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return AgendaEntry(
                id: item.id,
                kind: item.kind,
                title: (trimmed.isEmpty ? untitled : trimmed).projectionTruncated(to: limits.maxTitleLength),
                start: item.start,
                end: item.end,
                isAllDay: item.isAllDay,
                detail: item.detail?.projectionTruncated(to: limits.maxSubtitleLength),
                isCompleted: item.isCompleted,
                actionID: item.kind == .reminder ? toggleActionID(itemID: item.id) : nil
            )
        }
        return .agenda(
            AgendaTemplate(
                id: id,
                title: title.projectionTruncated(to: limits.maxTitleLength),
                entries: Array(entries),
                emptyMessage: emptyMessage.projectionTruncated(to: limits.maxSubtitleLength)
            )
        )
    }
}

/// The system music player's state as the companion read it.
public struct NowPlayingSnapshot: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var artwork: Data?
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artwork: Data? = nil,
        elapsed: TimeInterval = 0,
        duration: TimeInterval = 0,
        isPlaying: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.elapsed = elapsed
        self.duration = duration
        self.isPlaying = isPlaying
    }
}

public enum NowPlayingProjection {
    public static let rootTemplateID = "nowPlaying.root"

    /// Cleans up player values so the result always validates: times are clamped, oversized
    /// artwork is left out, and the commands match the playback state.
    public static func template(
        snapshot: NowPlayingSnapshot,
        idleTitle: String,
        limits: ProjectionLimits = .standard
    ) -> ProjectionTemplate {
        let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return .nowPlaying(
                NowPlayingTemplate(id: rootTemplateID, title: idleTitle.projectionTruncated(to: limits.maxTitleLength), commands: [.play])
            )
        }
        let duration = snapshot.duration.isFinite ? max(0, snapshot.duration) : 0
        let rawElapsed = snapshot.elapsed.isFinite ? max(0, snapshot.elapsed) : 0
        let elapsed = duration > 0 ? min(rawElapsed, duration) : rawElapsed
        let artwork = snapshot.artwork.flatMap { $0.count <= limits.maxArtworkBytes ? $0 : nil }
        return .nowPlaying(
            NowPlayingTemplate(
                id: rootTemplateID,
                title: title.projectionTruncated(to: limits.maxTitleLength),
                artist: snapshot.artist?.projectionTruncated(to: limits.maxTitleLength),
                album: snapshot.album?.projectionTruncated(to: limits.maxTitleLength),
                artwork: artwork,
                elapsed: elapsed,
                duration: duration,
                isPlaying: snapshot.isPlaying,
                commands: [.previousTrack, snapshot.isPlaying ? .pause : .play, .nextTrack, .restartTrack]
            )
        )
    }

    /// Where playback is now, given a template the hub received at `receivedAt` on its own clock.
    public static func elapsed(for template: NowPlayingTemplate, receivedAt: Date, now: Date) -> TimeInterval {
        guard template.isPlaying else { return template.elapsed }
        let advanced = template.elapsed + max(0, now.timeIntervalSince(receivedAt))
        return template.duration > 0 ? min(advanced, template.duration) : advanced
    }
}
