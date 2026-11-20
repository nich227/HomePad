import Foundation

/// Whose browser session a page belongs to.
public enum BrowserOwner: Hashable, Sendable {
    /// Nobody the hub recognizes. One session is shared by whoever is unrecognized, and it is
    /// forgotten when that person leaves.
    case guest
    case member(UUID)

    public init(activeProfileID: UUID?) {
        self = activeProfileID.map(BrowserOwner.member) ?? .guest
    }

    public var profileID: UUID? {
        switch self {
        case .guest: nil
        case .member(let id): id
        }
    }

    /// The owner of a page that just reached the hub. A paired iPhone speaks for the household
    /// member it was paired for, wherever that person is. Every other source is an action taken
    /// at the hub, so the page belongs to whoever is in front of it.
    /// - Parameters:
    ///   - senderProfileID: The member the sending iPhone was paired for.
    ///   - householdProfileIDs: The members the household has now. A page from an iPhone whose
    ///     member was removed would otherwise wait for someone who can never arrive.
    public static func owner(
        of source: BeamSource,
        senderProfileID: UUID?,
        householdProfileIDs: Set<UUID>,
        active: BrowserOwner
    ) -> BrowserOwner {
        guard case .peerLink = source, let senderProfileID, householdProfileIDs.contains(senderProfileID) else {
            return active
        }
        return .member(senderProfileID)
    }
}

/// Who is in front of the hub, as far as the browser cares: the audience and the count of sign
/// outs, both read from `HouseholdSession`.
public struct HubPresence: Equatable, Sendable {
    public let owner: BrowserOwner
    /// `HouseholdSession.audienceGeneration`. It changes exactly when the audience signs out.
    public let audienceGeneration: Int

    public init(activeProfileID: UUID?, audienceGeneration: Int) {
        self.owner = BrowserOwner(activeProfileID: activeProfileID)
        self.audienceGeneration = audienceGeneration
    }

    public static let nobody = HubPresence(activeProfileID: nil, audienceGeneration: 0)

    /// The person who signed out between `self` and `next`. The household session decides when
    /// that is and says so by changing the generation: at once for a lock, a switch by hand,
    /// another member's face, or a judged stranger in a member's place, and after the grace
    /// period when the camera just loses sight of someone. A person the camera lost sight of
    /// has not signed out, so their pages stay open and on screen. The owner cannot change
    /// without the generation changing. It is compared as well so that a page can never
    /// outlive its owner's turn at the hub.
    public func signedOut(by next: HubPresence) -> BrowserOwner? {
        next.audienceGeneration != audienceGeneration || next.owner != owner ? owner : nil
    }
}
