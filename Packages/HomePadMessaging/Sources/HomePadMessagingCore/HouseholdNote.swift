import Foundation

/// A short note sent between the hub and the household's companions.
public struct HouseholdNote: Codable, Sendable, Equatable, Identifiable {
    public let version: Int
    public let id: UUID
    public let senderName: String
    public let senderProfileID: UUID?
    public let text: String
    public let sentAt: Date

    public init(version: Int = HouseholdNoteCodec.version, id: UUID, senderName: String, senderProfileID: UUID?, text: String, sentAt: Date) {
        self.version = version
        self.id = id
        self.senderName = senderName
        self.senderProfileID = senderProfileID
        self.text = text
        self.sentAt = sentAt
    }
}

public enum HouseholdNoteError: Error, Equatable, Sendable {
    case emptyText
    case textTooLong(limit: Int)
    case emptySender
    case unsupportedVersion(Int)
    case malformed
}

public enum HouseholdNoteCodec {
    public static let version = 1
    public static let maxTextLength = 280
    public static let maxSenderLength = 80
    public static let maxPayloadBytes = 4096

    /// Trims and checks a note before it is sent.
    public static func make(
        id: UUID,
        senderName: String,
        senderProfileID: UUID?,
        text: String,
        sentAt: Date
    ) throws(HouseholdNoteError) -> HouseholdNote {
        let note = HouseholdNote(
            id: id,
            senderName: senderName.trimmingCharacters(in: .whitespacesAndNewlines),
            senderProfileID: senderProfileID,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: sentAt
        )
        try validate(note)
        return note
    }

    public static func encode(_ note: HouseholdNote) throws(HouseholdNoteError) -> Data {
        try validate(note)
        guard let data = try? JSONEncoder().encode(note) else { throw .malformed }
        return data
    }

    public static func decode(_ data: Data) throws(HouseholdNoteError) -> HouseholdNote {
        struct Header: Decodable { let version: Int }
        guard data.count <= maxPayloadBytes, let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw .malformed
        }
        guard header.version == version else { throw .unsupportedVersion(header.version) }
        guard let note = try? JSONDecoder().decode(HouseholdNote.self, from: data) else { throw .malformed }
        try validate(note)
        return note
    }

    private static func validate(_ note: HouseholdNote) throws(HouseholdNoteError) {
        guard note.version == version else { throw .unsupportedVersion(note.version) }
        guard !note.senderName.isEmpty, note.senderName.count <= maxSenderLength else { throw .emptySender }
        guard !note.text.isEmpty else { throw .emptyText }
        guard note.text.count <= maxTextLength else { throw .textTooLong(limit: maxTextLength) }
    }
}

/// The notes waiting to be shown as a banner, one at a time, each for a fixed time. Memory only.
public struct NoteBannerQueue: Sendable, Equatable {
    struct Shown: Sendable, Equatable {
        var note: HouseholdNote
        var since: Date
    }

    public let displayDuration: TimeInterval
    public let capacity: Int
    private var pending: [HouseholdNote] = []
    private var shown: Shown?
    private var seen: [UUID] = []

    public init(displayDuration: TimeInterval = 12, capacity: Int = 5) {
        self.displayDuration = displayDuration
        self.capacity = capacity
    }

    /// Returns false for a note that was already queued or shown.
    @discardableResult
    public mutating func enqueue(_ note: HouseholdNote, now: Date) -> Bool {
        guard !seen.contains(note.id) else { return false }
        seen.append(note.id)
        if seen.count > capacity * 4 {
            seen.removeFirst(seen.count - capacity * 4)
        }
        pending.append(note)
        if pending.count > capacity {
            pending.removeFirst(pending.count - capacity)
        }
        advance(now: now)
        return true
    }

    /// The note to show right now, after expiring one that has been up long enough.
    public mutating func current(now: Date) -> HouseholdNote? {
        advance(now: now)
        return shown?.note
    }

    public mutating func dismissCurrent(now: Date) {
        shown = nil
        advance(now: now)
    }

    public var pendingCount: Int { pending.count }

    private mutating func advance(now: Date) {
        if let shown, now.timeIntervalSince(shown.since) >= displayDuration {
            self.shown = nil
        }
        if shown == nil, !pending.isEmpty {
            shown = Shown(note: pending.removeFirst(), since: now)
        }
    }
}
