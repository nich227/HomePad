import Foundation

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

/// Which navigations the hub's browser follows once a page is open.
public enum BeamNavigationPolicy {
    public enum Decision: Equatable, Sendable {
        case allow
        case cancel
        /// A link that asked for a new window. The hub has one page, so it loads there.
        case loadInPlace
    }

    /// A page that changes what the whole view shows must pass the same policy as a beam, so a
    /// public page cannot redirect the hub to an address a beam could not have named.
    public static func decide(url: URL?, targetsMainFrame: Bool?, isDownload: Bool, policy: BeamURLPolicy) -> Decision {
        guard !isDownload, let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if targetsMainFrame == false {
            return ["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel
        }
        guard case .success = policy.validate(url) else { return .cancel }
        return targetsMainFrame == nil ? .loadInPlace : .allow
    }
}
