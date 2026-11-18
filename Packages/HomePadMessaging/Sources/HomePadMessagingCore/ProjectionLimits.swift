import Foundation

/// Bounds on what a companion may project. The hub renders any template inside these bounds
/// without knowing the app, so the bounds are what keep every app legible and glanceable.
public struct ProjectionLimits: Sendable, Equatable {
    public var maxApps = 12
    public var maxNavigationDepth = 5
    public var maxListSections = 8
    /// Across all sections of one list.
    public var maxListRows = 24
    public var maxGridButtons = 8
    public var maxConversations = 20
    public var maxBubbles = 40
    public var maxInformationItems = 12
    public var maxInformationButtons = 3
    public var maxAgendaEntries = 24
    public var maxIdentifierLength = 128
    public var maxTitleLength = 80
    public var maxSubtitleLength = 160
    public var maxBodyLength = 2000
    public var maxArtworkBytes = 96 * 1024
    /// One encoded frame, including base64 artwork.
    public var maxPayloadBytes = 256 * 1024
    public var maxActionPayloadEntries = 8

    public init() {}

    public static let standard = ProjectionLimits()
}

public enum ProjectionValidationError: Error, Equatable, Sendable {
    case invalidIdentifier(field: String)
    case duplicateIdentifier(field: String)
    case emptyText(field: String)
    case textTooLong(field: String, limit: Int)
    case tooManyItems(field: String, limit: Int)
    case invalidSymbolName(field: String)
    case invalidCount(field: String)
    case artworkTooLarge(limit: Int)
    case invalidPlaybackTime
    case navigationDepthExceeded(limit: Int)
}

extension String {
    /// Shortens text to a projection limit, ending with an ellipsis when something was cut.
    public func projectionTruncated(to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard count > limit else { return self }
        return String(prefix(limit - 1)) + "\u{2026}"
    }
}
