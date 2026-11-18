import Foundation

/// One fact the hub offers the Assistant, such as a timer, the weather, or a calendar event.
public struct AssistantContextItem: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case timer, weather, home, nowPlaying, playlist
        case calendarEvent, reminder

        /// Kinds that belong to one person whoever is named as the owner.
        public var isAlwaysPersonal: Bool {
            switch self {
            case .calendarEvent, .reminder: true
            case .timer, .weather, .home, .nowPlaying, .playlist: false
            }
        }
    }

    public let id: String
    public let kind: Kind
    /// The member the item belongs to. Nil for something the whole household shares.
    public let ownerID: UUID?
    public let title: String
    public let detail: String

    public init(id: String, kind: Kind, ownerID: UUID? = nil, title: String, detail: String = "") {
        self.id = id
        self.kind = kind
        self.ownerID = ownerID
        self.title = title
        self.detail = detail
    }

    /// An item with an owner is personal whatever its kind, and a personal kind with no owner
    /// is still personal, so it can never pass as shared.
    public var isPersonal: Bool {
        kind.isAlwaysPersonal || ownerID != nil
    }
}

/// Context that passed `AssistantPolicy.allowedContext`. Prompt assembly takes only this type.
public struct AssistantAllowedContext: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// The short name the model uses to say it relied on the item.
        public let tag: String
        public let item: AssistantContextItem
    }

    public let entries: [Entry]

    public static let none = AssistantAllowedContext(items: [])

    init(items: [AssistantContextItem]) {
        entries = items.enumerated().map { Entry(tag: "c\($0.offset + 1)", item: $0.element) }
    }

    public var items: [AssistantContextItem] { entries.map(\.item) }

    public var containsPersonalItems: Bool {
        entries.contains { $0.item.isPersonal }
    }

    /// The items behind the tags the model named, in the model's order, without repeats.
    public func items(tagged tags: [String]) -> [AssistantContextItem] {
        var seen: Set<String> = []
        return tags.compactMap { tag in
            guard seen.insert(tag).inserted else { return nil }
            return entries.first { $0.tag == tag }?.item
        }
    }
}

/// What the hub is doing, in the few facts every answer may need.
public struct AssistantHubState: Equatable, Sendable {
    public var hubName: String
    /// What is in front, for example "Clock face" or "Home app".
    public var screenTitle: String
    public var isNightMode: Bool
    public var usesFahrenheit: Bool

    public init(hubName: String = "HomePad", screenTitle: String = "", isNightMode: Bool = false, usesFahrenheit: Bool = false) {
        self.hubName = hubName
        self.screenTitle = screenTitle
        self.isNightMode = isNightMode
        self.usesFahrenheit = usesFahrenheit
    }
}

/// Numbers that bound what goes to the model, what comes back, and how long each step may take.
public enum AssistantLimits {
    public static let maxRequestCharacters = 400
    public static let maxContextItems = 8
    public static let maxContextTextCharacters = 140
    public static let maxToolTextCharacters = 400
    public static let maxNameCharacters = 60
    public static let maxNoteCharacters = 500
    public static let maxAddressCharacters = 2048
    public static let maxAnswerCharacters = 480
    public static let maxSpokenCharacters = 280
    public static let maxSpokenSentences = 3
    public static let maxFollowUps = 3
    public static let maxFollowUpCharacters = 36
    public static let maxSnippets = 3
    public static let maxActionsPerTurn = 6
    public static let maximumResponseTokens = 260
    public static let timerSecondsRange = 1...86_400
    public static let thermostatCelsiusRange = 5.0...35.0

    public static let noSpeechTimeout: TimeInterval = 8
    /// Silence after speech that ends the request.
    public static let endOfSpeechPause: TimeInterval = 1.6
    public static let responseTimeout: TimeInterval = 30
    public static let tickInterval: TimeInterval = 0.5
}
