import Foundation

public enum BeamApprovalMode: String, Sendable, CaseIterable, Equatable {
    case askFirst
    case openImmediately

    /// Unknown stored values fall back to asking.
    public init(settingValue: String) {
        self = BeamApprovalMode(rawValue: settingValue) ?? .askFirst
    }
}

/// How a page reached the hub.
public enum BeamSource: Equatable, Sendable {
    case peerLink(deviceID: UUID)
    case sharePlay
    case handoff
    case deepLink
}

public enum BeamAskReason: String, Equatable, Sendable {
    case hubPrefersAsking
    case guestSession
    case firstBeamFromDevice
    case untrustedSource
}

public enum BeamApprovalDecision: Equatable, Sendable {
    case openNow
    case ask(BeamAskReason)
}

public enum BeamApprovalPolicy {
    /// - Parameters:
    ///   - isGuest: Nobody in front of the hub is recognized.
    ///   - senderApprovedBeamCount: Beams from this device that someone at the hub has opened.
    public static func decide(
        source: BeamSource,
        mode: BeamApprovalMode,
        isGuest: Bool,
        senderApprovedBeamCount: Int
    ) -> BeamApprovalDecision {
        switch source {
        case .deepLink:
            // Any app or web page on the hub can open the URL scheme.
            return .ask(.untrustedSource)
        case .handoff, .sharePlay:
            // Both start from an action taken on the hub itself: picking up the activity, or
            // joining the session.
            return .openNow
        case .peerLink:
            if mode == .askFirst { return .ask(.hubPrefersAsking) }
            if isGuest { return .ask(.guestSession) }
            if senderApprovedBeamCount <= 0 { return .ask(.firstBeamFromDevice) }
            return .openNow
        }
    }
}
