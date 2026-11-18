import Foundation
import HomePadCore

public enum ProjectedAppCategory: String, Codable, Sendable, CaseIterable {
    case communication, productivity, audio, information
}

/// An app that runs on a companion iPhone and shows on the hub through templates.
public struct ProjectedApp: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    /// SF Symbol name.
    public var symbolName: String
    public var tint: RainbowTint
    public var category: ProjectedAppCategory
    /// True when the app shows content that belongs to the companion's owner.
    public var requiresPersonalContent: Bool

    public init(
        id: String,
        name: String,
        symbolName: String,
        tint: RainbowTint,
        category: ProjectedAppCategory,
        requiresPersonalContent: Bool
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.category = category
        self.requiresPersonalContent = requiresPersonalContent
    }
}

public enum ProjectionRowAccessory: Codable, Sendable, Equatable {
    case none
    case disclosure
    case toggle(isOn: Bool)
    case badge(count: Int)
    case detail(String)
}

public struct ProjectionRow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var symbolName: String?
    public var accessory: ProjectionRowAccessory
    /// Sent back to the companion when the row is tapped. `nil` rows are not tappable.
    public var actionID: String?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String? = nil,
        accessory: ProjectionRowAccessory = .none,
        actionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory
        self.actionID = actionID
    }
}

public struct ProjectionSection: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var header: String?
    public var rows: [ProjectionRow]

    public init(id: String, header: String? = nil, rows: [ProjectionRow]) {
        self.id = id
        self.header = header
        self.rows = rows
    }
}

public struct ListTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var sections: [ProjectionSection]
    /// Shown when there are no rows.
    public var emptyMessage: String?

    public init(id: String, title: String, sections: [ProjectionSection], emptyMessage: String? = nil) {
        self.id = id
        self.title = title
        self.sections = sections
        self.emptyMessage = emptyMessage
    }
}

public struct ProjectionButton: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var symbolName: String?
    public var actionID: String

    public init(id: String, title: String, symbolName: String? = nil, actionID: String) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.actionID = actionID
    }
}

public struct GridTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var buttons: [ProjectionButton]

    public init(id: String, title: String, buttons: [ProjectionButton]) {
        self.id = id
        self.title = title
        self.buttons = buttons
    }
}

public enum MediaCommand: String, Codable, Sendable, CaseIterable {
    case play, pause, nextTrack, previousTrack, restartTrack
}

public struct NowPlayingTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// Track title, or a short idle message when nothing is playing.
    public var title: String
    public var artist: String?
    public var album: String?
    /// Encoded image data (JPEG or PNG), bounded by `ProjectionLimits.maxArtworkBytes`.
    public var artwork: Data?
    public var elapsed: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool
    public var commands: [MediaCommand]

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        artwork: Data? = nil,
        elapsed: TimeInterval = 0,
        duration: TimeInterval = 0,
        isPlaying: Bool = false,
        commands: [MediaCommand] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.elapsed = elapsed
        self.duration = duration
        self.isPlaying = isPlaying
        self.commands = commands
    }
}

public struct InformationItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String
    public var value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct InformationTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var items: [InformationItem]
    public var buttons: [ProjectionButton]

    public init(id: String, title: String, items: [InformationItem], buttons: [ProjectionButton] = []) {
        self.id = id
        self.title = title
        self.items = items
        self.buttons = buttons
    }
}

public enum AgendaEntryKind: String, Codable, Sendable {
    case event, reminder
}

public struct AgendaEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var kind: AgendaEntryKind
    public var title: String
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    /// Location for an event, list name for a reminder.
    public var detail: String?
    public var isCompleted: Bool
    public var actionID: String?

    public init(
        id: String,
        kind: AgendaEntryKind,
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        detail: String? = nil,
        isCompleted: Bool = false,
        actionID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.detail = detail
        self.isCompleted = isCompleted
        self.actionID = actionID
    }
}

public struct AgendaTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var entries: [AgendaEntry]
    public var emptyMessage: String?

    public init(id: String, title: String, entries: [AgendaEntry], emptyMessage: String? = nil) {
        self.id = id
        self.title = title
        self.entries = entries
        self.emptyMessage = emptyMessage
    }
}

public enum ProjectionTemplateKind: String, Sendable, CaseIterable {
    case list, grid, nowPlaying, information, agenda
}

/// One screen of a projected app. The set of cases is the whole vocabulary: a companion cannot
/// send custom views, and a hub that does not know a case rejects the frame.
public enum ProjectionTemplate: Codable, Sendable, Equatable, Identifiable {
    case list(ListTemplate)
    case grid(GridTemplate)
    case nowPlaying(NowPlayingTemplate)
    case information(InformationTemplate)
    case agenda(AgendaTemplate)

    public var id: String {
        switch self {
        case .list(let template): template.id
        case .grid(let template): template.id
        case .nowPlaying(let template): template.id
        case .information(let template): template.id
        case .agenda(let template): template.id
        }
    }

    public var title: String {
        switch self {
        case .list(let template): template.title
        case .grid(let template): template.title
        case .nowPlaying(let template): template.title
        case .information(let template): template.title
        case .agenda(let template): template.title
        }
    }

    public var kind: ProjectionTemplateKind {
        switch self {
        case .list: .list
        case .grid: .grid
        case .nowPlaying: .nowPlaying
        case .information: .information
        case .agenda: .agenda
        }
    }
}
