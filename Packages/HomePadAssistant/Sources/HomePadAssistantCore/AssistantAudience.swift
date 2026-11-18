import Foundation
import HomePadCore

/// Who is in front of the hub, reduced to what the Assistant's rules depend on.
public struct AssistantAudience: Equatable, Sendable {
    /// The active household member. Nil for a guest.
    public let memberID: UUID?
    public let memberName: String?
    /// The camera recognized the member's face. A profile picked by hand is not recognized.
    public let isRecognized: Bool
    public let isPersonalContentUnlocked: Bool

    public static let guest = AssistantAudience(memberID: nil, memberName: nil, isRecognized: false, isPersonalContentUnlocked: false)

    /// A guest is never recognized, and personal content is never unlocked without recognition,
    /// whatever the arguments say.
    public init(memberID: UUID?, memberName: String?, isRecognized: Bool, isPersonalContentUnlocked: Bool) {
        self.memberID = memberID
        self.memberName = memberID == nil ? nil : memberName
        self.isRecognized = memberID != nil && isRecognized
        self.isPersonalContentUnlocked = memberID != nil && isRecognized && isPersonalContentUnlocked
    }

    @MainActor
    public init(session: HouseholdSession) {
        let profile = session.activeProfile
        var isRecognized = false
        if case .face = session.activation {
            isRecognized = true
        }
        self.init(
            memberID: profile?.id,
            memberName: profile?.name,
            isRecognized: isRecognized,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked
        )
    }

    public var isGuest: Bool { memberID == nil }
}

/// Who may ask for something.
public enum AssistantAccess: Equatable, Sendable {
    /// Anyone in front of the hub, recognized or not.
    case anyone
    /// An active household profile, however it was selected.
    case member
    /// A member the camera recognized.
    case recognizedMember
}

/// The kinds of things the Assistant can do. Access mirrors the hub: shared things are open to
/// a guest, things done in a member's name need a member, and scenes need a recognized face.
public enum AssistantCapability: String, CaseIterable, Sendable {
    case timers, navigation, nightMode, weather, accessories, climate, screen
    case browser, notes
    case scenes

    public var access: AssistantAccess {
        switch self {
        case .timers, .navigation, .nightMode, .weather, .accessories, .climate, .screen: .anyone
        case .browser, .notes: .member
        case .scenes: .recognizedMember
        }
    }
}

public enum AssistantPolicy {
    /// Why this audience may not use a capability. Nil means it may.
    public static func denial(for capability: AssistantCapability, audience: AssistantAudience) -> AssistantActionError? {
        switch capability.access {
        case .anyone:
            nil
        case .member:
            audience.isGuest ? .needsHouseholdMember : nil
        case .recognizedMember:
            audience.isRecognized ? nil : .needsRecognizedMember
        }
    }

    public static func capabilities(for audience: AssistantAudience) -> [AssistantCapability] {
        AssistantCapability.allCases.filter { denial(for: $0, audience: audience) == nil }
    }

    /// The only way to make context the model may see. A personal item passes only while the
    /// member it belongs to has personal content unlocked. Everything else about a person is
    /// dropped here, before any prompt exists.
    public static func allowedContext(
        _ items: [AssistantContextItem],
        audience: AssistantAudience,
        usesPersonalContext: Bool
    ) -> AssistantAllowedContext {
        var seen: Set<String> = []
        let allowed = items.filter { item in
            guard seen.insert(item.id).inserted else { return false }
            guard item.isPersonal else { return true }
            guard usesPersonalContext, audience.isPersonalContentUnlocked, let owner = item.ownerID else { return false }
            return owner == audience.memberID
        }
        return AssistantAllowedContext(items: Array(allowed.prefix(AssistantLimits.maxContextItems)))
    }
}
