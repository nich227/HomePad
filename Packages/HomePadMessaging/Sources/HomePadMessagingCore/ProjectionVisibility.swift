import Foundation

/// Who is in front of the hub, as plain values.
public struct ViewerContext: Sendable, Equatable {
    public var activeProfileID: UUID?
    public var isPersonalContentUnlocked: Bool

    public init(activeProfileID: UUID?, isPersonalContentUnlocked: Bool) {
        self.activeProfileID = activeProfileID
        self.isPersonalContentUnlocked = isPersonalContentUnlocked
    }

    public static let nobody = ViewerContext(activeProfileID: nil, isPersonalContentUnlocked: false)
}

public enum ContentVisibility: String, Sendable, Equatable {
    case visible
    /// Show that the app exists, without any of its content.
    case redacted
    case hidden
}

public enum VisibilityReason: String, Sendable, Equatable {
    /// The app shows nothing personal.
    case sharedContent
    /// The owner was recognized by face.
    case ownerVerified
    /// The owner's profile is selected but personal content is locked.
    case ownerNotVerified
    /// The companion is not linked to a household member.
    case noOwner
    case someoneElsePresent
    case nobodyRecognized
}

public struct VisibilityDecision: Sendable, Equatable {
    public let visibility: ContentVisibility
    public let reason: VisibilityReason

    public init(visibility: ContentVisibility, reason: VisibilityReason) {
        self.visibility = visibility
        self.reason = reason
    }
}

public enum ProjectionVisibilityPolicy {
    /// A companion's personal content is visible only to its owner, and only while the hub has
    /// personal content unlocked. A different member or a guest does not learn that it exists.
    public static func decide(
        ownerProfileID: UUID?,
        requiresPersonalContent: Bool,
        viewer: ViewerContext
    ) -> VisibilityDecision {
        guard requiresPersonalContent else {
            return VisibilityDecision(visibility: .visible, reason: .sharedContent)
        }
        guard let ownerProfileID else {
            return VisibilityDecision(visibility: .hidden, reason: .noOwner)
        }
        guard let activeProfileID = viewer.activeProfileID else {
            return VisibilityDecision(visibility: .hidden, reason: .nobodyRecognized)
        }
        guard activeProfileID == ownerProfileID else {
            return VisibilityDecision(visibility: .hidden, reason: .someoneElsePresent)
        }
        guard viewer.isPersonalContentUnlocked else {
            return VisibilityDecision(visibility: .redacted, reason: .ownerNotVerified)
        }
        return VisibilityDecision(visibility: .visible, reason: .ownerVerified)
    }
}
