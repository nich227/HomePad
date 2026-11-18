import Foundation
import HomePadCore

public enum HandoffError: Error, Equatable, Sendable {
    case unsupportedActivityType
    case missingURL
}

/// The fields of the Handoff activity a companion advertises for the page it is about to send.
public struct HandoffPayload: Equatable, Sendable {
    public static let urlKey = "url"
    public static let titleKey = "title"

    public let urlText: String
    public let title: String?

    public init(urlText: String, title: String?) {
        self.urlText = urlText
        self.title = BeamText.sanitizedTitle(title)
    }

    public var userInfo: [String: String] {
        var info = [Self.urlKey: urlText]
        if let title { info[Self.titleKey] = title }
        return info
    }

    /// Reads an activity the system handed to the hub. Accepts this app's beam activity and the
    /// system web browsing activity.
    public static func parse(
        activityType: String,
        webpageURL: URL?,
        userInfo: [AnyHashable: Any]?
    ) throws(HandoffError) -> HandoffPayload {
        switch activityType {
        case HomePadIdentifiers.beamActivityType:
            let text = (userInfo?[urlKey] as? String) ?? webpageURL?.absoluteString
            guard let text, !text.isEmpty else { throw .missingURL }
            return HandoffPayload(urlText: text, title: userInfo?[titleKey] as? String)
        case NSUserActivityTypeBrowsingWeb:
            guard let webpageURL else { throw .missingURL }
            return HandoffPayload(urlText: webpageURL.absoluteString, title: nil)
        default:
            throw .unsupportedActivityType
        }
    }
}
