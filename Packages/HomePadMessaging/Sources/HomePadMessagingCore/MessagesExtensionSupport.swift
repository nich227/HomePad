import Foundation
import HomePadCore

/// A page that was recently sent to a hub, offered again by the iMessage extension.
public struct RecentPage: Codable, Sendable, Equatable, Identifiable {
    public let url: URL
    public let title: String?
    public let beamedAt: Date

    public var id: String { url.absoluteString }

    public init(url: URL, title: String?, beamedAt: Date) {
        self.url = url
        self.title = title
        self.beamedAt = beamedAt
    }
}

/// What the hub is showing, in a form that can be shared into a conversation.
public struct SharedHubItem: Codable, Sendable, Equatable {
    public let title: String
    /// App-scheme form of a `MessageDeepLink`.
    public let link: URL
    public let updatedAt: Date

    public init(title: String, link: URL, updatedAt: Date) {
        self.title = title
        self.link = link
        self.updatedAt = updatedAt
    }
}

/// The small amount of state the app shares with its iMessage extension through the app group
/// defaults. The app writes; the extension only reads. It holds page URLs and titles, never
/// message text, and nothing is stored while "Suggest Recent Pages in Messages" is off.
public struct MessagesExtensionStore {
    public static let recentPagesKey = "messaging.shared.recentPages"
    public static let hubItemKey = "messaging.shared.hubItem"
    public static let maxRecentPages = 8
    /// A hub item older than this no longer describes what is on the hub.
    public static let hubItemLifetime: TimeInterval = 10 * 60

    private let defaults: UserDefaults

    /// Pass `UserDefaults(suiteName: HomePadIdentifiers.appGroup)`.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var suggestsRecentPages: Bool {
        defaults.object(forKey: MessagingSettings.suggestRecentPages.name) as? Bool
            ?? MessagingSettings.suggestRecentPages.defaultValue
    }

    // MARK: Read (extension)

    /// Newest first. Empty when suggestions are off or the stored data is unreadable.
    public func recentPages() -> [RecentPage] {
        guard suggestsRecentPages,
              let data = defaults.data(forKey: Self.recentPagesKey),
              let pages = try? JSONDecoder().decode([RecentPage].self, from: data)
        else { return [] }
        let valid = pages.filter { (try? MessageDeepLinkCodec.validatedPage($0.url.absoluteString)) != nil }
        return Array(valid.sorted { $0.beamedAt > $1.beamedAt }.prefix(Self.maxRecentPages))
    }

    public func hubItem(now: Date) -> SharedHubItem? {
        guard let data = defaults.data(forKey: Self.hubItemKey),
              let item = try? JSONDecoder().decode(SharedHubItem.self, from: data),
              now.timeIntervalSince(item.updatedAt) < Self.hubItemLifetime,
              (try? MessageDeepLinkCodec.decode(item.link)) != nil
        else { return nil }
        return item
    }

    // MARK: Write (app)

    /// Remembers a page the app just sent to a hub. Clears the list instead when suggestions are off.
    public func record(_ page: RecentPage) {
        guard suggestsRecentPages, (try? MessageDeepLinkCodec.validatedPage(page.url.absoluteString)) != nil else {
            if !suggestsRecentPages {
                defaults.removeObject(forKey: Self.recentPagesKey)
            }
            return
        }
        var pages = recentPages().filter { $0.id != page.id }
        pages.insert(page, at: 0)
        if let data = try? JSONEncoder().encode(Array(pages.prefix(Self.maxRecentPages))) {
            defaults.set(data, forKey: Self.recentPagesKey)
        }
    }

    /// Publishes what the hub is showing, or clears it with `nil`.
    public func setHubItem(_ item: SharedHubItem?) {
        guard let item, let data = try? JSONEncoder().encode(item) else {
            defaults.removeObject(forKey: Self.hubItemKey)
            return
        }
        defaults.set(data, forKey: Self.hubItemKey)
    }
}

/// The content of an interactive message bubble, ready to be turned into an `MSMessage`.
public struct MessageCard: Sendable, Equatable {
    public let caption: String
    public let subcaption: String?
    /// Goes in `MSMessage.url`.
    public let messageURL: URL
    public let symbolName: String
}

public enum MessagesExtensionLogic {
    public static let maxCaptionLength = 80

    /// Builds the bubble for a link. `title` is the page or app title when known.
    public static func card(for link: MessageDeepLink, title: String?) throws(MessageDeepLinkError) -> MessageCard {
        let messageURL = try MessageDeepLinkCodec.messageURL(for: link)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (cleanTitle?.isEmpty ?? true) ? nil : cleanTitle?.projectionTruncated(to: maxCaptionLength)
        switch link {
        case .beamPage(let page):
            let host = try MessageDeepLinkCodec.validatedPageAndHost(page.absoluteString).host
            return MessageCard(caption: named ?? host, subcaption: named == nil ? nil : host, messageURL: messageURL, symbolName: "globe")
        case .openApp(let id):
            return MessageCard(caption: named ?? id, subcaption: nil, messageURL: messageURL, symbolName: "square.grid.2x2")
        case .openFace(let id):
            return MessageCard(caption: named ?? id, subcaption: nil, messageURL: messageURL, symbolName: "clock")
        }
    }

    /// A page URL from pasted or typed text. A bare host such as `example.com` gets `https`.
    public static func pageURL(fromText text: String?) -> URL? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace)
        else { return nil }
        if let url = try? MessageDeepLinkCodec.validatedPage(trimmed) {
            return url
        }
        guard !trimmed.contains("://"), trimmed.contains(".") else { return nil }
        return try? MessageDeepLinkCodec.validatedPage("https://" + trimmed)
    }

    /// What to offer for a message someone selected in the conversation: the decoded link and the
    /// URL that opens it in the containing app. `nil` for anything that is not a valid HomePad link.
    public static func openAction(forMessageURL url: URL?) -> (link: MessageDeepLink, appURL: URL)? {
        guard let url, let link = try? MessageDeepLinkCodec.decode(url),
              let appURL = try? MessageDeepLinkCodec.appURL(for: link)
        else { return nil }
        return (link, appURL)
    }
}
