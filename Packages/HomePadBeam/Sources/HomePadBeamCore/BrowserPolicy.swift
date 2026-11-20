import Foundation
import HomePadCore

/// Which cookie and storage jar the hub's browser uses.
public enum BrowserDataStore: Equatable, Sendable {
    /// Nothing is written to disk and nothing carries over to the next page session.
    case ephemeral
    case profile(UUID)

    /// Sign-ins are personal content, so a persistent jar is used only while the active profile's
    /// personal content is unlocked. Guests and manually picked profiles browse without one.
    public static func choice(isPersonalContentUnlocked: Bool, activeProfileID: UUID?) -> BrowserDataStore {
        guard isPersonalContentUnlocked, let activeProfileID else { return .ephemeral }
        return .profile(activeProfileID)
    }
}

/// Which navigations the hub's browser follows once a page is open. The browser never hands a
/// navigation to another app and never downloads.
public enum BeamNavigationPolicy {
    public enum Decision: Equatable, Sendable {
        case allow
        case cancel
        /// Cancel, then load the same address as a request the app makes itself. The system
        /// offers an address a person tapped to the app that claims it. It does not do that for
        /// a load the app starts.
        case loadInPlace
        /// A link that asked for a new window. It opens as another page of the same session.
        case openInNewPage
    }

    /// What started a navigation.
    public enum Trigger: Equatable, Sendable {
        case link
        case form
        case backForward
        case reload
        case other
    }

    public static let subframeSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
    /// Files the system would show in a viewer of its own, which has a share button.
    public static let systemViewerExtensions: Set<String> = ["usdz", "reality"]

    /// A page that changes what the whole view shows must pass the same policy as a beam, so a
    /// public page cannot redirect the hub to an address a beam could not have named.
    /// - Parameters:
    ///   - targetsMainFrame: `nil` when the navigation asked for a new window.
    ///   - isGet: Whether the request carries no body. Only such a request can be made again.
    ///   - currentURL: The address the page shows now.
    ///   - isOwnRequest: Whether the app itself started this load.
    public static func decide(
        url: URL?,
        targetsMainFrame: Bool?,
        isDownload: Bool,
        trigger: Trigger,
        isGet: Bool,
        currentURL: URL?,
        isOwnRequest: Bool,
        policy: BeamURLPolicy
    ) -> Decision {
        guard !isDownload, let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if targetsMainFrame == false {
            return subframeSchemes.contains(scheme) ? .allow : .cancel
        }
        guard case .success = policy.validate(url), !systemViewerExtensions.contains(url.pathExtension.lowercased()) else {
            return .cancel
        }
        if targetsMainFrame == nil { return .openInNewPage }
        if isOwnRequest || !isGet { return .allow }
        switch trigger {
        case .form, .backForward, .reload:
            return .allow
        case .link, .other:
            return isSameSite(url, currentURL) ? .allow : .loadInPlace
        }
    }

    /// A response is shown only when the web view can render it in place. Anything else, and
    /// anything the server marks as an attachment, would be a download.
    public static func allowsResponse(canShowMimeType: Bool, contentDisposition: String?) -> Bool {
        guard canShowMimeType else { return false }
        let disposition = contentDisposition?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return !disposition.hasPrefix("attachment")
    }

    private static func isSameSite(_ url: URL, _ other: URL?) -> Bool {
        guard let other else { return false }
        return url.scheme?.lowercased() == other.scheme?.lowercased()
            && url.host()?.lowercased() == other.host()?.lowercased()
            && url.port == other.port
    }
}

/// Which iPhone the page in front can be sent back to.
public enum SendBackPolicy {
    /// The iPhone that beamed the page, when it is connected and is not another member's. Else
    /// the connected iPhone of the member who owns the session. A guest has no iPhone of their
    /// own, so a guest's page goes back only to the iPhone it came from.
    public static func target(pageSource: BeamSource?, owner: BrowserOwner, connected: [PeerDevice]) -> PeerDevice? {
        if case .peerLink(let deviceID) = pageSource,
           let device = connected.first(where: { $0.id == deviceID }),
           device.profileID == nil || device.profileID == owner.profileID {
            return device
        }
        guard let profileID = owner.profileID else { return nil }
        return connected.first { $0.profileID == profileID }
    }
}
