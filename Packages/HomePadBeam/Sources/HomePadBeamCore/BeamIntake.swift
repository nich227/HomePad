import Foundation

/// A beam that passed the URL policy and was approved to open.
public struct ApprovedBeam: Equatable, Sendable, Identifiable {
    public let payload: BeamPayload
    public let url: ValidatedURL
    public let source: BeamSource

    public var id: UUID { payload.id }
}

/// A beam the hub is holding for its owner.
public struct WaitingBeam: Equatable, Sendable, Identifiable {
    public let payload: BeamPayload
    public let source: BeamSource
    public let receivedAt: Date
    /// Why the hub asks before opening. `nil` until the owner has been in front of the hub with
    /// the beam waiting, because nothing is decided, and nothing is shown, before then.
    public fileprivate(set) var askReason: BeamAskReason?

    public var id: UUID { payload.id }

    fileprivate var outcome: BeamOutcome {
        askReason == nil ? .waitingForOwner : .awaitingApproval
    }
}

public enum BeamIntakeResult: Equatable, Sendable {
    case open(ApprovedBeam)
    case pending(BeamPayload, BeamAskReason)
    /// The owner is not the person in front of the hub. The page is held, unseen, for them.
    case waitingForOwner(BeamPayload)
    /// The same page from the same device is already held. The value is where that one stands.
    case duplicate(BeamOutcome)
    case rateLimited
    case rejected(BeamURLRejection)

    /// What to tell the sender.
    public var outcome: BeamOutcome {
        switch self {
        case .open: .opened
        case .pending: .awaitingApproval
        case .waitingForOwner: .waitingForOwner
        case .duplicate(let outcome): outcome
        case .rateLimited: .rateLimited
        case .rejected(let reason): .rejected(reason)
        }
    }
}

/// An answer for the paired iPhone that sent a beam.
public struct BeamReceiptNotice: Equatable, Sendable {
    public let deviceID: UUID
    public let receipt: BeamReceipt
}

/// The hub's whole decision path for an incoming page: rate limit, URL policy, owner, approval,
/// and the browser session it opens in.
///
/// A beam whose owner is not in front of the hub is held for that owner and shown to nobody
/// else. It is decided when the owner is next in front: it opens, or the hub asks, as the
/// approval policy says at that moment.
public struct BeamIntake: Sendable {
    public static let beamsPerWindow = 6
    public static let window: TimeInterval = 30
    public static let defaultWaitingLimit = 6
    public static let defaultWaitingLifetime: TimeInterval = 30 * 60

    public private(set) var browser: BrowserSessions
    /// Beams held for one owner. When one more arrives, the oldest is let go.
    public let waitingLimit: Int
    public let waitingLifetime: TimeInterval

    private var limiter: RateLimiter<UUID>
    /// Oldest first.
    private var waiting: [BrowserOwner: [WaitingBeam]] = [:]
    private var receipts: [BeamReceiptNotice] = []

    public init(
        browser: BrowserSessions = BrowserSessions(),
        limit: Int = BeamIntake.beamsPerWindow,
        window: TimeInterval = BeamIntake.window,
        waitingLimit: Int = BeamIntake.defaultWaitingLimit,
        waitingLifetime: TimeInterval = BeamIntake.defaultWaitingLifetime
    ) {
        self.browser = browser
        self.limiter = RateLimiter(limit: limit, window: window)
        self.waitingLimit = max(1, waitingLimit)
        self.waitingLifetime = waitingLifetime
    }

    /// The person in front of the hub, as last told to `presenceChanged`.
    public var active: BrowserOwner { browser.presence.owner }

    /// The beams the hub is asking the viewer about. Oldest first. Empty unless the viewer is the
    /// person in front of the hub, and never holds a beam that belongs to someone else.
    public func offers(for viewer: BrowserOwner) -> [BeamPayload] {
        guard viewer == active else { return [] }
        return (waiting[viewer] ?? []).filter { $0.askReason != nil }.map(\.payload)
    }

    /// How many beams are held for an owner, decided or not.
    public func waitingCount(for owner: BrowserOwner) -> Int {
        waiting[owner]?.count ?? 0
    }

    /// When the next held beam runs out, so the caller can come back then.
    public var nextExpiry: Date? {
        waiting.values.joined().map(\.receivedAt).min()?.addingTimeInterval(waitingLifetime)
    }

    /// Hands over the answers that built up for senders since the last call.
    public mutating func takeReceipts() -> [BeamReceiptNotice] {
        defer { receipts = [] }
        return receipts
    }

    // MARK: Arrivals

    /// - Parameters:
    ///   - senderProfileID: The household member the sending iPhone was paired for.
    ///   - householdProfileIDs: The members the household has now.
    ///   - senderApprovedBeamCount: Beams from this device that someone at the hub has opened.
    ///   - dataStore: The jar a page gets if it opens now for the person in front.
    public mutating func receive(
        _ beam: BeamPayload,
        source: BeamSource,
        senderProfileID: UUID?,
        householdProfileIDs: Set<UUID>,
        preferences: BeamPreferences,
        senderApprovedBeamCount: Int,
        dataStore: BrowserDataStore,
        now: Date
    ) -> BeamIntakeResult {
        pruneExpired(now: now)
        let result = decide(
            beam,
            source: source,
            senderProfileID: senderProfileID,
            householdProfileIDs: householdProfileIDs,
            preferences: preferences,
            senderApprovedBeamCount: senderApprovedBeamCount,
            dataStore: dataStore,
            now: now
        )
        note(result.outcome, for: beam.id, source: source)
        return result
    }

    /// Tells the intake who is in front of the hub now. Someone who signed out has every page
    /// closed, and a guest's held beams are dropped with the rest of the guest session. Then
    /// what was held for the person now in front is decided.
    /// - Parameters:
    ///   - approvedBeamCount: Beams from a device that someone at the hub has opened.
    ///   - dataStore: The jar a held page gets if it opens now.
    @discardableResult
    public mutating func presenceChanged(
        to presence: HubPresence,
        preferences: BeamPreferences,
        approvedBeamCount: (UUID) -> Int,
        dataStore: BrowserDataStore,
        now: Date
    ) -> BrowserSignOut? {
        pruneExpired(now: now)
        let signOut = browser.update(to: presence)
        if signOut?.owner == .guest {
            for entry in waiting.removeValue(forKey: .guest) ?? [] {
                note(.expired, for: entry.id, source: entry.source)
            }
        }
        decideHeld(for: active, preferences: preferences, approvedBeamCount: approvedBeamCount, dataStore: dataStore, now: now)
        return signOut
    }

    // MARK: Answers from the person in front

    /// The person in front chose to open a beam the hub asked them about. The URL is checked
    /// again because the local-address preference may have changed while it waited.
    public mutating func approve(id: UUID, preferences: BeamPreferences, dataStore: BrowserDataStore, now: Date) -> ApprovedBeam? {
        guard let entry = takeOffer(id: id) else { return nil }
        switch preferences.urlPolicy.validate(entry.payload.url) {
        case .failure(let reason):
            note(.rejected(reason), for: id, source: entry.source)
            return nil
        case .success(let url):
            let approved = ApprovedBeam(payload: entry.payload, url: url, source: entry.source)
            browser.open(approved, keepHistory: preferences.keepHistory, dataStore: dataStore, now: now)
            note(.opened, for: id, source: entry.source)
            return approved
        }
    }

    @discardableResult
    public mutating func decline(id: UUID) -> BeamPayload? {
        guard let entry = takeOffer(id: id) else { return nil }
        note(.declined, for: id, source: entry.source)
        return entry.payload
    }

    /// Opens a page again from the recents of the person in front. A page that is not in their
    /// own recents does not open.
    public mutating func reopen(recentID: UUID, preferences: BeamPreferences, dataStore: BrowserDataStore, now: Date) -> ApprovedBeam? {
        guard let beam = browser.recents(for: active).first(where: { $0.id == recentID }),
              case .success(let url) = preferences.urlPolicy.validate(beam.url)
        else { return nil }
        let approved = ApprovedBeam(payload: beam, url: url, source: .deepLink)
        browser.open(approved, keepHistory: preferences.keepHistory, dataStore: dataStore, now: now)
        return approved
    }

    // MARK: Pages

    public mutating func openChildPage(of parentID: UUID, url: ValidatedURL, id: UUID, now: Date) -> BrowserPage? {
        browser.openChild(of: parentID, url: url, id: id, now: now)
    }

    public mutating func selectPage(_ pageID: UUID) {
        browser.select(pageID)
    }

    public mutating func closePage(_ pageID: UUID) {
        browser.close(pageID)
    }

    public mutating func closeAllPages() {
        browser.closeAll()
    }

    public mutating func putAway() {
        browser.putAway()
    }

    // MARK: Upkeep

    public mutating func applyHistoryPreference(keepHistory: Bool) {
        if !keepHistory { browser.clearRecents() }
    }

    /// Lets go of beams held longer than `waitingLifetime` and tells their senders.
    @discardableResult
    public mutating func pruneExpired(now: Date) -> [BeamPayload] {
        let cutoff = now.addingTimeInterval(-waitingLifetime)
        var expired: [WaitingBeam] = []
        for (owner, entries) in waiting {
            expired += entries.filter { $0.receivedAt <= cutoff }
            waiting[owner] = entries.filter { $0.receivedAt > cutoff }
        }
        expired.sort { $0.receivedAt < $1.receivedAt }
        for entry in expired {
            note(.expired, for: entry.id, source: entry.source)
        }
        return expired.map(\.payload)
    }

    /// Drops everything a device sent that is not an open page, for when it is revoked.
    public mutating func forget(deviceID: UUID) {
        for owner in waiting.keys {
            waiting[owner]?.removeAll { $0.payload.sender.id == deviceID }
        }
        receipts.removeAll { $0.deviceID == deviceID }
        browser.forgetRecents(from: deviceID)
        limiter.reset(deviceID)
    }

    // MARK: Private

    private mutating func decide(
        _ beam: BeamPayload,
        source: BeamSource,
        senderProfileID: UUID?,
        householdProfileIDs: Set<UUID>,
        preferences: BeamPreferences,
        senderApprovedBeamCount: Int,
        dataStore: BrowserDataStore,
        now: Date
    ) -> BeamIntakeResult {
        if case .peerLink(let deviceID) = source, !limiter.allow(deviceID, now: now) {
            return .rateLimited
        }
        let url: ValidatedURL
        switch preferences.urlPolicy.validate(beam.url) {
        case .success(let validated): url = validated
        case .failure(let reason): return .rejected(reason)
        }
        let owner = BrowserOwner.owner(
            of: source,
            senderProfileID: senderProfileID,
            householdProfileIDs: householdProfileIDs,
            active: active
        )
        guard owner == active else {
            return hold(beam, source: source, for: owner, askReason: nil, now: now) ?? .waitingForOwner(beam)
        }
        let decision = BeamApprovalPolicy.decide(
            source: source,
            mode: preferences.approvalMode,
            isGuest: owner == .guest,
            senderApprovedBeamCount: senderApprovedBeamCount
        )
        switch decision {
        case .openNow:
            let approved = ApprovedBeam(payload: beam, url: url, source: source)
            browser.open(approved, keepHistory: preferences.keepHistory, dataStore: dataStore, now: now)
            return .open(approved)
        case .ask(let reason):
            return hold(beam, source: source, for: owner, askReason: reason, now: now) ?? .pending(beam, reason)
        }
    }

    /// Returns `.duplicate` when the same page from the same device is already held for the
    /// owner, and `nil` when the beam was added.
    private mutating func hold(
        _ beam: BeamPayload,
        source: BeamSource,
        for owner: BrowserOwner,
        askReason: BeamAskReason?,
        now: Date
    ) -> BeamIntakeResult? {
        var entries = waiting[owner] ?? []
        if let held = entries.first(where: { $0.id == beam.id || ($0.payload.url == beam.url && $0.payload.sender.id == beam.sender.id) }) {
            return .duplicate(held.outcome)
        }
        entries.append(WaitingBeam(payload: beam, source: source, receivedAt: now, askReason: askReason))
        while entries.count > waitingLimit {
            let dropped = entries.removeFirst()
            note(.expired, for: dropped.id, source: dropped.source)
        }
        waiting[owner] = entries
        return nil
    }

    /// Decides the beams that arrived while their owner was away, oldest first, so the newest
    /// one that opens ends up in front.
    private mutating func decideHeld(
        for owner: BrowserOwner,
        preferences: BeamPreferences,
        approvedBeamCount: (UUID) -> Int,
        dataStore: BrowserDataStore,
        now: Date
    ) {
        var kept: [WaitingBeam] = []
        for var entry in waiting[owner] ?? [] {
            guard entry.askReason == nil else {
                kept.append(entry)
                continue
            }
            let url: ValidatedURL
            switch preferences.urlPolicy.validate(entry.payload.url) {
            case .success(let validated):
                url = validated
            case .failure(let reason):
                note(.rejected(reason), for: entry.id, source: entry.source)
                continue
            }
            var approvedCount = 0
            if case .peerLink(let deviceID) = entry.source {
                approvedCount = approvedBeamCount(deviceID)
            }
            let decision = BeamApprovalPolicy.decide(
                source: entry.source,
                mode: preferences.approvalMode,
                isGuest: owner == .guest,
                senderApprovedBeamCount: approvedCount
            )
            switch decision {
            case .openNow:
                let approved = ApprovedBeam(payload: entry.payload, url: url, source: entry.source)
                browser.open(approved, keepHistory: preferences.keepHistory, dataStore: dataStore, now: now)
                note(.opened, for: entry.id, source: entry.source)
            case .ask(let reason):
                entry.askReason = reason
                kept.append(entry)
                note(.awaitingApproval, for: entry.id, source: entry.source)
            }
        }
        waiting[owner] = kept
    }

    /// Takes a beam the hub asked the person in front about out of the held list.
    private mutating func takeOffer(id: UUID) -> WaitingBeam? {
        guard let index = waiting[active]?.firstIndex(where: { $0.id == id && $0.askReason != nil }) else { return nil }
        return waiting[active]?.remove(at: index)
    }

    private mutating func note(_ outcome: BeamOutcome, for beamID: UUID, source: BeamSource) {
        guard case .peerLink(let deviceID) = source else { return }
        receipts.append(BeamReceiptNotice(deviceID: deviceID, receipt: BeamReceipt(beamID: beamID, outcome: outcome)))
    }
}
