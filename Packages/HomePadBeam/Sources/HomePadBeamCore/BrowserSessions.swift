import Foundation

/// One open page of a browser session.
public struct BrowserPage: Identifiable, Equatable, Sendable {
    /// What the page was opened from. A page that a link opened in a new window carries a beam
    /// made for it, attributed to the sender of the page the link was on.
    public let beam: ApprovedBeam
    /// The cookie and storage jar the page uses. It is chosen when the page opens and never
    /// changes while the page is open, so a page is not reloaded under the person reading it.
    public let dataStore: BrowserDataStore
    public let openedAt: Date

    public var id: UUID { beam.id }
}

/// What a sign out closed.
public struct BrowserSignOut: Equatable, Sendable {
    public let owner: BrowserOwner
    public let closedPageIDs: [UUID]
}

/// The hub's browser: one session per owner, each with its open pages and its recent pages.
///
/// Two rules hold everywhere in this type. Pages open only in the session of the person in front
/// of the hub. Every question about a session is asked on behalf of a viewer and is answered
/// only when that viewer is the person in front of the hub, so nobody is shown another person's
/// pages, titles, addresses, or recents.
public struct BrowserSessions: Sendable {
    public static let defaultPageLimit = 6
    public static let defaultRecentsLimit = 50

    public let pageLimit: Int
    public let recentsLimit: Int
    public private(set) var presence: HubPresence

    private struct Session: Sendable {
        /// Oldest first.
        var pages: [BrowserPage] = []
        var frontID: UUID?
        /// Whether the session asks for the screen. Opening or choosing a page sets it.
        var isOnScreen = false
        /// A beam that another part of the app shows instead of the browser.
        var handOff: ApprovedBeam?
        /// Newest first.
        var recents: [BeamPayload] = []
    }

    private var sessions: [BrowserOwner: Session] = [:]

    public init(
        pageLimit: Int = BrowserSessions.defaultPageLimit,
        recentsLimit: Int = BrowserSessions.defaultRecentsLimit,
        presence: HubPresence = .nobody
    ) {
        self.pageLimit = max(1, pageLimit)
        self.recentsLimit = max(0, recentsLimit)
        self.presence = presence
    }

    // MARK: What a viewer may see

    /// Oldest first.
    public func pages(for viewer: BrowserOwner) -> [BrowserPage] {
        session(for: viewer)?.pages ?? []
    }

    public func frontPage(for viewer: BrowserOwner) -> BrowserPage? {
        guard let session = session(for: viewer) else { return nil }
        return session.pages.first { $0.id == session.frontID }
    }

    /// The beam the hub should put on screen: a hand-off if one is waiting to be taken, else the
    /// page in front while the session asks for the screen.
    public func presented(for viewer: BrowserOwner) -> ApprovedBeam? {
        guard let session = session(for: viewer) else { return nil }
        if let handOff = session.handOff { return handOff }
        return session.isOnScreen ? frontPage(for: viewer)?.beam : nil
    }

    /// Newest first.
    public func recents(for viewer: BrowserOwner) -> [BeamPayload] {
        session(for: viewer)?.recents ?? []
    }

    /// Every page that is open, whoever owns it. It carries no titles or addresses, so the web
    /// views of pages that are no longer listed can be let go.
    public var openPageIDs: Set<UUID> {
        Set(sessions.values.flatMap { $0.pages.map(\.id) })
    }

    // MARK: What the person in front of the hub does

    /// Opens a beam for the person in front of the hub. A recipe is handed off instead of
    /// becoming a page. A beam that is already open comes to the front. When the session is
    /// full, the oldest page that is not in front closes.
    /// - Parameter dataStore: The jar a new page gets, from `BrowserDataStore.choice` at this
    ///   moment.
    public mutating func open(_ beam: ApprovedBeam, keepHistory: Bool, dataStore: BrowserDataStore, now: Date) {
        var session = sessions[presence.owner] ?? Session()
        if keepHistory {
            session.recents.removeAll { $0.url == beam.payload.url }
            session.recents.insert(beam.payload, at: 0)
            session.recents = Array(session.recents.prefix(recentsLimit))
        }
        if beam.payload.kind == .recipe {
            session.handOff = beam
        } else {
            if !session.pages.contains(where: { $0.id == beam.id }) {
                makeRoom(in: &session)
                session.pages.append(BrowserPage(beam: beam, dataStore: dataStore, openedAt: now))
            }
            session.frontID = beam.id
            session.isOnScreen = true
        }
        sessions[presence.owner] = session
    }

    /// Opens the address a link asked to show in a new window, as another page of the session
    /// that holds `parentID`, with that page's jar, so a sign-in that opens a window still
    /// works. Returns `nil` when that page is not open for the person in front.
    public mutating func openChild(of parentID: UUID, url: ValidatedURL, id: UUID, now: Date) -> BrowserPage? {
        guard let parent = sessions[presence.owner]?.pages.first(where: { $0.id == parentID }) else { return nil }
        let payload = BeamPayload(id: id, url: url.url, title: nil, sender: parent.beam.payload.sender, sentAt: now)
        let child = ApprovedBeam(payload: payload, url: url, source: parent.beam.source)
        open(child, keepHistory: false, dataStore: parent.dataStore, now: now)
        return frontPage(for: presence.owner)
    }

    /// Brings a page to the front and asks for the screen.
    public mutating func select(_ pageID: UUID) {
        guard var session = sessions[presence.owner], session.pages.contains(where: { $0.id == pageID }) else { return }
        session.frontID = pageID
        session.isOnScreen = true
        sessions[presence.owner] = session
    }

    /// Closes one page. When it was in front, the page opened after it takes its place, or the
    /// one before it when it was the newest.
    public mutating func close(_ pageID: UUID) {
        guard var session = sessions[presence.owner], let index = session.pages.firstIndex(where: { $0.id == pageID }) else {
            return
        }
        session.pages.remove(at: index)
        if session.frontID == pageID {
            session.frontID = session.pages.indices.contains(index) ? session.pages[index].id : session.pages.last?.id
        }
        if session.pages.isEmpty { session.isOnScreen = false }
        sessions[presence.owner] = session
    }

    public mutating func closeAll() {
        guard var session = sessions[presence.owner] else { return }
        session.pages = []
        session.frontID = nil
        session.isOnScreen = false
        sessions[presence.owner] = session
    }

    /// Takes the browser off the screen and drops a hand-off. Open pages stay open.
    public mutating func putAway() {
        guard var session = sessions[presence.owner] else { return }
        session.isOnScreen = false
        session.handOff = nil
        sessions[presence.owner] = session
    }

    // MARK: Recents

    public mutating func clearRecents() {
        for owner in sessions.keys {
            sessions[owner]?.recents = []
        }
    }

    /// Drops the recent pages a device sent, for when it is revoked.
    public mutating func forgetRecents(from deviceID: UUID) {
        for owner in sessions.keys {
            sessions[owner]?.recents.removeAll { $0.sender.id == deviceID }
        }
    }

    // MARK: Sign out

    /// Records who is in front of the hub now. When the household session says someone signed
    /// out, every page of theirs closes, and a guest's session is forgotten whole. A member's
    /// recents stay for the next time they are in front.
    @discardableResult
    public mutating func update(to next: HubPresence) -> BrowserSignOut? {
        let departing = presence.signedOut(by: next)
        presence = next
        guard let departing else { return nil }
        let closed = sessions[departing]?.pages.map(\.id) ?? []
        if departing == .guest {
            sessions[departing] = nil
        } else {
            sessions[departing]?.pages = []
            sessions[departing]?.frontID = nil
            sessions[departing]?.isOnScreen = false
            sessions[departing]?.handOff = nil
        }
        return BrowserSignOut(owner: departing, closedPageIDs: closed)
    }

    // MARK: Private

    private func session(for viewer: BrowserOwner) -> Session? {
        guard viewer == presence.owner else { return nil }
        return sessions[viewer]
    }

    private func makeRoom(in session: inout Session) {
        while session.pages.count >= pageLimit {
            let index = session.pages.firstIndex { $0.id != session.frontID } ?? 0
            session.pages.remove(at: index)
        }
    }
}
