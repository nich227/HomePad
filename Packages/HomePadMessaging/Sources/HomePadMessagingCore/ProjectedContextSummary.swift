import Foundation

/// One short fact from a member's projected content, as plain text for a consumer that does not
/// know the templates.
///
/// The text left `MemoryOnly`, so the same rule applies to this value: keep it in memory, and
/// never save or log it.
public struct ProjectedContextSummary: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case calendarEvent, reminder, nowPlaying
    }

    /// The same for the same agenda entry or player on the same companion. It is built from
    /// identifiers only, never from the text.
    public let id: String
    public let kind: Kind
    /// The member whose iPhone projected the item.
    public let ownerProfileID: UUID
    /// The event or reminder name, or the track.
    public let title: String
    /// The event's time and place, the reminder's due time and list, or the artist and album.
    /// Empty when the companion sent none of that.
    public let detail: String

    public init(id: String, kind: Kind, ownerProfileID: UUID, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.ownerProfileID = ownerProfileID
        self.title = title
        self.detail = detail
    }
}

@available(*, unavailable, message: "Projected content must not be encoded or persisted.")
extension ProjectedContextSummary: Encodable {
    public func encode(to encoder: any Encoder) throws {}
}

@available(*, unavailable, message: "Projected content must not be decoded from storage.")
extension ProjectedContextSummary: Decodable {
    public init(from decoder: any Decoder) throws { throw CancellationError() }
}

/// The screens of one projected app that the person in front of the hub is allowed to see.
public struct ProjectedContextSource: Sendable, Equatable {
    public let entryID: ProjectedAppEntryID
    public let ownerProfileID: UUID
    /// Root first.
    public let templates: [ProjectionTemplate]

    public init(entryID: ProjectedAppEntryID, ownerProfileID: UUID, templates: [ProjectionTemplate]) {
        self.entryID = entryID
        self.ownerProfileID = ownerProfileID
        self.templates = templates
    }
}

/// How event and due times are written. The hub's own locale and time zone, unless a test fixes them.
public struct ProjectedContextTimeStyle: Sendable, Equatable {
    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.locale = locale
        self.timeZone = timeZone
    }

    public static var current: ProjectedContextTimeStyle { ProjectedContextTimeStyle() }
}

public enum ProjectedContextSummarizer {
    private struct Candidate {
        let summary: ProjectedContextSummary
        /// Lower comes first within a kind.
        let rank: TimeInterval
    }

    /// Turns templates into summaries. The caller decides whose templates may be read; this only
    /// reads them.
    ///
    /// A kind comes from the template itself: an agenda entry says whether it is an event or a
    /// reminder, and a player that is playing gives now playing. Every other template gives
    /// nothing. Left out: events that have ended, completed reminders, and a player that is not
    /// playing.
    ///
    /// Events and reminders are soonest first with undated ones last. The kinds take turns, so
    /// `limit` shortens every kind instead of dropping the last ones, and any prefix of the result
    /// is balanced the same way.
    ///
    /// `maxTextLength` counts characters as a person reads them, and applies to the title and to
    /// the detail separately. Clipped text ends with an ellipsis.
    public static func summaries(
        from sources: [ProjectedContextSource],
        limit: Int,
        maxTextLength: Int,
        now: Date,
        timeStyle: ProjectedContextTimeStyle = .current
    ) -> [ProjectedContextSummary] {
        guard limit > 0, maxTextLength > 0 else { return [] }
        var seenIDs: Set<String> = []
        var seenText: Set<[String]> = []
        let candidates = sources
            .flatMap { source in
                source.templates.flatMap { candidates(in: $0, source: source, maxTextLength: maxTextLength, now: now, timeStyle: timeStyle) }
            }
            .filter { candidate in
                // Two companions of one member can project the same event, and one app can show an item on two screens.
                let summary = candidate.summary
                guard !summary.title.isEmpty, seenIDs.insert(summary.id).inserted else { return false }
                return seenText.insert([summary.kind.rawValue, summary.title, summary.detail]).inserted
            }
        let queues = ProjectedContextSummary.Kind.allCases.map { kind in
            candidates
                .filter { $0.summary.kind == kind }
                .sorted { ($0.rank, $0.summary.id) < ($1.rank, $1.summary.id) }
                .map(\.summary)
        }
        let longest = queues.reduce(0) { max($0, $1.count) }
        let turns = (0..<longest).flatMap { turn in queues.compactMap { turn < $0.count ? $0[turn] : nil } }
        return Array(turns.prefix(limit))
    }

    private static func candidates(
        in template: ProjectionTemplate,
        source: ProjectedContextSource,
        maxTextLength: Int,
        now: Date,
        timeStyle: ProjectedContextTimeStyle
    ) -> [Candidate] {
        func candidate(_ kind: ProjectedContextSummary.Kind, itemID: String, title: String, detail: [String?], rank: TimeInterval) -> Candidate {
            Candidate(
                summary: ProjectedContextSummary(
                    id: [source.entryID.deviceID.uuidString, source.entryID.appID, kind.rawValue, itemID].joined(separator: "/"),
                    kind: kind,
                    ownerProfileID: source.ownerProfileID,
                    title: clipped(title, to: maxTextLength),
                    detail: clipped(detail.compactMap { $0 }.map(folded).filter { !$0.isEmpty }.joined(separator: ", "), to: maxTextLength)
                ),
                rank: rank
            )
        }
        switch template {
        case .agenda(let agenda):
            return agenda.entries.compactMap { entry in
                let rank = entry.start?.timeIntervalSinceReferenceDate ?? .infinity
                let detail = [whenText(for: entry, timeStyle: timeStyle), entry.detail]
                switch entry.kind {
                case .event:
                    // The hub's copy is as old as the companion's last send, so an event can end while the hub still holds it.
                    if let end = entry.end, end <= now { return nil }
                    return candidate(.calendarEvent, itemID: entry.id, title: entry.title, detail: detail, rank: rank)
                case .reminder:
                    if entry.isCompleted { return nil }
                    return candidate(.reminder, itemID: entry.id, title: entry.title, detail: detail, rank: rank)
                }
            }
        case .nowPlaying(let player):
            // A stopped player's title is a status line, not a track.
            guard player.isPlaying else { return [] }
            return [candidate(.nowPlaying, itemID: player.id, title: player.title, detail: [player.artist, player.album], rank: 0)]
        case .list, .grid, .information:
            return []
        }
    }

    private static func whenText(for entry: AgendaEntry, timeStyle: ProjectedContextTimeStyle) -> String? {
        guard let start = entry.start else { return nil }
        var calendar = timeStyle.locale.calendar
        calendar.timeZone = timeStyle.timeZone
        let day = Date.FormatStyle(locale: timeStyle.locale, calendar: calendar, timeZone: timeStyle.timeZone)
            .weekday(.abbreviated).month(.abbreviated).day()
        if entry.isAllDay {
            return start.formatted(day)
        }
        if entry.kind == .event, let end = entry.end, end > start {
            let interval = Date.IntervalFormatStyle(locale: timeStyle.locale, calendar: calendar, timeZone: timeStyle.timeZone)
                .weekday(.abbreviated).month(.abbreviated).day().hour().minute()
            return (start..<end).formatted(interval)
        }
        return start.formatted(day.hour().minute())
    }

    /// One line with single spaces, so a length limit counts text and not layout.
    private static func folded(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `String` counts and cuts by grapheme cluster, so an emoji sequence or an accented letter is never split.
    private static func clipped(_ text: String, to length: Int) -> String {
        folded(text).projectionTruncated(to: length)
    }
}
