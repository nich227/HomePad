import Foundation
import HomePadCore

/// What a HomePad link inside a Messages conversation, or a `homepad://message` URL, may ask for.
/// Pairing is deliberately absent: a link received in a conversation can never start pairing.
public enum MessageDeepLink: Sendable, Equatable {
    /// Show a web page on the hub.
    case beamPage(URL)
    case openApp(id: String)
    case openFace(id: String)
}

public enum MessageDeepLinkError: Error, Equatable, Sendable {
    case notAMessageLink
    case tooLong
    case malformed
    case unsupportedVersion
    case unknownKind
    /// A kind that exists elsewhere in the app but is refused in message links.
    case kindNotAllowed
    case missingParameter
    case invalidPageURL
    case invalidIdentifier
}

public enum MessageDeepLinkCodec {
    public static let version = 1
    public static let maxLength = 2048
    public static let maxPageURLLength = 1800
    public static let maxIdentifierLength = 64
    /// Host of the app-scheme form, `homepad://message?...`.
    public static let appURLHost = "message"
    /// The form an `MSMessage` carries. `MSMessage.url` takes HTTP(S) or data URLs only.
    public static let messageURLPrefix = "data:application/vnd.homepad.link,"

    private static let refusedKinds: Set<String> = ["pair", "pairing", "invite"]
    private static let valueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static let identifierAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")

    // MARK: Encoding

    /// `homepad://message?v=1&kind=...`, which opens the containing app.
    public static func appURL(for link: MessageDeepLink) throws(MessageDeepLinkError) -> URL {
        try url(from: "\(HomePadIdentifiers.urlScheme)://\(appURLHost)?" + query(for: link))
    }

    /// The URL to put in `MSMessage.url`.
    public static func messageURL(for link: MessageDeepLink) throws(MessageDeepLinkError) -> URL {
        try url(from: messageURLPrefix + query(for: link))
    }

    private static func url(from string: String) throws(MessageDeepLinkError) -> URL {
        guard string.count <= maxLength else { throw .tooLong }
        guard let url = URL(string: string) else { throw .malformed }
        return url
    }

    private static func query(for link: MessageDeepLink) throws(MessageDeepLinkError) -> String {
        let kind: String
        let name: String
        let value: String
        switch link {
        case .beamPage(let page):
            kind = "beam"
            name = "url"
            value = try validatedPage(page.absoluteString).absoluteString
        case .openApp(let id):
            kind = "app"
            name = "id"
            value = try validatedIdentifier(id)
        case .openFace(let id):
            kind = "face"
            name = "id"
            value = try validatedIdentifier(id)
        }
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: valueAllowed) else { throw .malformed }
        return "v=\(version)&kind=\(kind)&\(name)=\(encoded)"
    }

    // MARK: Decoding

    /// Accepts both forms. Anything unexpected is an error: an unknown or repeated parameter, an
    /// unknown kind, a version other than the current one, or a page URL that is not plain
    /// `http` or `https`.
    public static func decode(_ url: URL) throws(MessageDeepLinkError) -> MessageDeepLink {
        let text = url.absoluteString
        let rawQuery: String
        if text.hasPrefix(messageURLPrefix) {
            rawQuery = String(text.dropFirst(messageURLPrefix.count))
        } else if url.scheme?.lowercased() == HomePadIdentifiers.urlScheme, url.host()?.lowercased() == appURLHost {
            guard url.path().isEmpty || url.path() == "/", url.fragment == nil else { throw .malformed }
            rawQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        } else {
            throw .notAMessageLink
        }
        guard text.count <= maxLength else { throw .tooLong }

        var parameters: [String: String] = [:]
        for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let value = String(parts[1]).removingPercentEncoding else { throw .malformed }
            let name = String(parts[0])
            guard parameters.updateValue(value, forKey: name) == nil else { throw .malformed }
        }

        guard let versionText = parameters.removeValue(forKey: "v"), let kind = parameters.removeValue(forKey: "kind") else {
            throw .missingParameter
        }
        guard versionText == String(version) else { throw .unsupportedVersion }
        guard !refusedKinds.contains(kind) else { throw .kindNotAllowed }

        let link: MessageDeepLink
        switch kind {
        case "beam":
            guard let page = parameters.removeValue(forKey: "url") else { throw .missingParameter }
            link = .beamPage(try validatedPage(page))
        case "app":
            guard let id = parameters.removeValue(forKey: "id") else { throw .missingParameter }
            link = .openApp(id: try validatedIdentifier(id))
        case "face":
            guard let id = parameters.removeValue(forKey: "id") else { throw .missingParameter }
            link = .openFace(id: try validatedIdentifier(id))
        default:
            throw .unknownKind
        }
        guard parameters.isEmpty else { throw .malformed }
        return link
    }

    // MARK: Validation

    /// A page the hub may load: `http` or `https`, with a host, no embedded credentials.
    public static func validatedPage(_ text: String) throws(MessageDeepLinkError) -> URL {
        try validatedPageAndHost(text).url
    }

    static func validatedPageAndHost(_ text: String) throws(MessageDeepLinkError) -> (url: URL, host: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxPageURLLength,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url
        else { throw .invalidPageURL }
        return (url, host)
    }

    private static func validatedIdentifier(_ id: String) throws(MessageDeepLinkError) -> String {
        guard !id.isEmpty, id.count <= maxIdentifierLength, id.unicodeScalars.allSatisfy(identifierAllowed.contains) else {
            throw .invalidIdentifier
        }
        return id
    }
}
