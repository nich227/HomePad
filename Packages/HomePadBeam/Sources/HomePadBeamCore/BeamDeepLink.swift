import Foundation
import HomePadCore

public enum BeamDeepLinkError: Error, Equatable, Sendable {
    case notHomePadLink
    case unsupportedAction
    case missingURL
}

/// The `homepad://` links this package owns. The page address in a beam link is returned as
/// text; it still has to pass `BeamURLPolicy` before anything loads.
public enum BeamDeepLink: Equatable, Sendable {
    public static let beamHost = "beam"
    public static let urlQueryName = "url"
    public static let titleQueryName = "title"

    case beam(urlText: String, title: String?)
    /// The full invitation text, to hand to `PairingInvitation.parse`.
    case pair(code: String)

    public static func parse(_ url: URL) throws(BeamDeepLinkError) -> BeamDeepLink {
        guard url.scheme?.lowercased() == HomePadIdentifiers.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw .notHomePadLink }
        let items = components.queryItems ?? []
        switch components.host?.lowercased() {
        case beamHost:
            guard let text = items.first(where: { $0.name == urlQueryName })?.value, !text.isEmpty else {
                throw .missingURL
            }
            let title = items.first { $0.name == titleQueryName }?.value
            return .beam(urlText: text, title: BeamText.sanitizedTitle(title))
        case PairingInvitation.host:
            return .pair(code: url.absoluteString)
        default:
            throw .unsupportedAction
        }
    }

    /// A link that beams `page` to the HomePad app on the same device.
    public static func beamLink(for page: URL, title: String?) -> URL? {
        var components = URLComponents()
        components.scheme = HomePadIdentifiers.urlScheme
        components.host = beamHost
        var items = [URLQueryItem(name: urlQueryName, value: page.absoluteString)]
        if let title = BeamText.sanitizedTitle(title) {
            items.append(URLQueryItem(name: titleQueryName, value: title))
        }
        components.queryItems = items
        return components.url
    }
}
