import Foundation
import HomePadCore

/// Everything that decides how a reply typed on the hub can be delivered.
public struct ReplyContext: Sendable, Equatable {
    /// The member whose companion projected the conversation.
    public var conversationOwner: UUID?
    /// That companion, when it is still connected.
    public var companionDeviceID: UUID?
    public var viewer: ViewerContext
    /// Whether the conversation template allows replies at all.
    public var canReply: Bool
    /// Whether the hub itself can show the system message sheet.
    public var hubCanSendText: Bool
    /// The member whose Messages account is signed in on the hub, if any.
    public var hubMessagesAccountOwner: UUID?

    public init(
        conversationOwner: UUID?,
        companionDeviceID: UUID?,
        viewer: ViewerContext,
        canReply: Bool,
        hubCanSendText: Bool,
        hubMessagesAccountOwner: UUID?
    ) {
        self.conversationOwner = conversationOwner
        self.companionDeviceID = companionDeviceID
        self.viewer = viewer
        self.canReply = canReply
        self.hubCanSendText = hubCanSendText
        self.hubMessagesAccountOwner = hubMessagesAccountOwner
    }
}

public enum ReplyUnavailableReason: String, Sendable, Equatable {
    /// The conversation's owner is not the verified person in front of the hub.
    case personalContentLocked
    case conversationReadOnly
    case companionNotConnected
}

/// Where the person confirms the send. There is no route without one.
public enum ReplyConfirmationSite: String, Sendable, Equatable {
    case hub, companion
}

public enum ReplyRoute: Sendable, Equatable {
    /// The hub shows the system message sheet, prefilled. The person taps Send there.
    case composeOnHub
    /// The text goes to the companion, which shows the system message sheet for its owner to send.
    case handOffToCompanion(deviceID: UUID)
    case unavailable(ReplyUnavailableReason)

    public var confirmationSite: ReplyConfirmationSite? {
        switch self {
        case .composeOnHub: .hub
        case .handOffToCompanion: .companion
        case .unavailable: nil
        }
    }
}

public enum ReplyRouting {
    /// The hub composes only when its own Messages account belongs to the conversation's owner.
    /// Otherwise a reply sent from the hub would go out under someone else's name, so it is
    /// handed to the owner's iPhone instead. Either way the system sheet requires a tap to send.
    public static func route(_ context: ReplyContext) -> ReplyRoute {
        guard let owner = context.conversationOwner,
              context.viewer.activeProfileID == owner,
              context.viewer.isPersonalContentUnlocked
        else { return .unavailable(.personalContentLocked) }
        guard context.canReply else { return .unavailable(.conversationReadOnly) }
        if context.hubCanSendText, context.hubMessagesAccountOwner == owner {
            return .composeOnHub
        }
        if let deviceID = context.companionDeviceID {
            return .handOffToCompanion(deviceID: deviceID)
        }
        return .unavailable(.companionNotConnected)
    }

    /// Resolves the name typed in Settings to a household member. An ambiguous or unknown name
    /// resolves to nobody, which keeps replies on the companion route.
    public static func hubAccountOwner(named name: String, in profiles: [HouseholdProfile]) -> UUID? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let matches = profiles.filter { $0.name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return matches.count == 1 ? matches[0].id : nil
    }
}
