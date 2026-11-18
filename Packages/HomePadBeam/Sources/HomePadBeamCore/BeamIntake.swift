import Foundation

/// A beam that passed the URL policy and was approved to open.
public struct ApprovedBeam: Equatable, Sendable, Identifiable {
    public let payload: BeamPayload
    public let url: ValidatedURL
    public let source: BeamSource

    public var id: UUID { payload.id }
}

public enum BeamIntakeResult: Equatable, Sendable {
    case open(ApprovedBeam)
    case pending(BeamPayload, BeamAskReason)
    case duplicate
    case rateLimited
    case rejected(BeamURLRejection)

    /// What to tell the sender.
    public var outcome: BeamOutcome {
        switch self {
        case .open: .opened
        case .pending, .duplicate: .awaitingApproval
        case .rateLimited: .rateLimited
        case .rejected(let reason): .rejected(reason)
        }
    }
}

/// The hub's whole decision path for an incoming page: rate limit, URL policy, approval, inbox.
public struct BeamIntake: Sendable {
    public static let beamsPerWindow = 6
    public static let window: TimeInterval = 30

    public private(set) var inbox: BeamInbox
    private var limiter: RateLimiter<UUID>
    private var sources: [UUID: BeamSource] = [:]

    public init(inbox: BeamInbox = BeamInbox(), limit: Int = BeamIntake.beamsPerWindow, window: TimeInterval = BeamIntake.window) {
        self.inbox = inbox
        self.limiter = RateLimiter(limit: limit, window: window)
    }

    public mutating func receive(
        _ beam: BeamPayload,
        source: BeamSource,
        preferences: BeamPreferences,
        isGuest: Bool,
        senderApprovedBeamCount: Int,
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
        let decision = BeamApprovalPolicy.decide(
            source: source,
            mode: preferences.approvalMode,
            isGuest: isGuest,
            senderApprovedBeamCount: senderApprovedBeamCount
        )
        switch decision {
        case .openNow:
            return .open(opened(beam, url: url, source: source, keepHistory: preferences.keepHistory))
        case .ask(let reason):
            switch inbox.enqueue(beam, now: now) {
            case .duplicate:
                return .duplicate
            case .queued:
                sources[beam.id] = source
                sources = sources.filter { id, _ in inbox.pending.contains { $0.id == id } }
                return .pending(beam, reason)
            }
        }
    }

    /// Someone at the hub chose to open a waiting beam. The URL is checked again because the
    /// local-address preference may have changed while it waited.
    public mutating func approve(id: UUID, preferences: BeamPreferences) -> ApprovedBeam? {
        let source = sources.removeValue(forKey: id) ?? .deepLink
        guard let beam = inbox.resolve(id: id), case .success(let url) = preferences.urlPolicy.validate(beam.url) else {
            return nil
        }
        return opened(beam, url: url, source: source, keepHistory: preferences.keepHistory)
    }

    public mutating func decline(id: UUID) -> (beam: BeamPayload, source: BeamSource)? {
        let source = sources.removeValue(forKey: id) ?? .deepLink
        return inbox.resolve(id: id).map { ($0, source) }
    }

    /// Reopens a page from the recents list.
    public mutating func reopen(_ beam: BeamPayload, preferences: BeamPreferences) -> ApprovedBeam? {
        guard case .success(let url) = preferences.urlPolicy.validate(beam.url) else { return nil }
        return opened(beam, url: url, source: .deepLink, keepHistory: preferences.keepHistory)
    }

    public mutating func applyHistoryPreference(keepHistory: Bool) {
        if !keepHistory { inbox.clearHistory() }
    }

    @discardableResult
    public mutating func pruneExpired(now: Date) -> [BeamPayload] {
        let expired = inbox.pruneExpired(now: now)
        for beam in expired {
            sources[beam.id] = nil
        }
        return expired
    }

    public mutating func forget(deviceID: UUID) {
        for beam in inbox.pending where beam.sender.id == deviceID {
            sources[beam.id] = nil
        }
        inbox.removeAll(from: deviceID)
        limiter.reset(deviceID)
    }

    private mutating func opened(_ beam: BeamPayload, url: ValidatedURL, source: BeamSource, keepHistory: Bool) -> ApprovedBeam {
        if keepHistory { inbox.recordOpened(beam) }
        return ApprovedBeam(payload: beam, url: url, source: source)
    }
}
