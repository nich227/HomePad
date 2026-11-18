import Foundation

/// What one analyzed frame says about who is in front of the camera.
public enum FrameIdentity: Equatable, Sendable {
    case noFace
    /// A face is there but could not be judged (poor quality, extreme pose, no embedding).
    case unusable
    /// A face is there and matches no enrolled profile.
    case unmatched
    case matched(UUID)
}

public enum PresenceDecision: Equatable, Sendable {
    case nobody
    case unknownPerson
    case recognized(UUID)
}

public struct StabilizerPolicy: Equatable, Sendable {
    /// Number of recent judged frames considered.
    public var windowSize: Int
    /// Matches of one profile needed within the window to recognize it.
    public var requiredMatches: Int
    /// Matches of any other profile tolerated in the window. More than this means the identity is
    /// contested, which locks instead of switching back and forth.
    public var maximumCompetingMatches: Int
    /// Consecutive judged frames that are not the recognized profile before it is dropped.
    public var missesToDrop: Int
    /// Seconds a recognized profile is kept with a face present but no fresh match.
    public var matchTimeout: TimeInterval
    /// Seconds without any face before the decision becomes `nobody`.
    public var absenceTimeout: TimeInterval

    public init(
        windowSize: Int = 5,
        requiredMatches: Int = 3,
        maximumCompetingMatches: Int = 1,
        missesToDrop: Int = 3,
        matchTimeout: TimeInterval = 3,
        absenceTimeout: TimeInterval = 3
    ) {
        self.windowSize = max(1, windowSize)
        self.requiredMatches = min(max(1, requiredMatches), self.windowSize)
        self.maximumCompetingMatches = max(0, maximumCompetingMatches)
        self.missesToDrop = max(1, missesToDrop)
        self.matchTimeout = max(0, matchTimeout)
        self.absenceTimeout = max(0, absenceTimeout)
    }
}

/// Turns noisy per-frame matches into a steady decision. Timestamps are seconds on any
/// monotonic clock supplied by the caller.
public struct RecognitionStabilizer: Sendable {
    private struct Entry: Sendable {
        let time: TimeInterval
        let profileID: UUID?
    }

    public let policy: StabilizerPolicy
    public private(set) var decision: PresenceDecision = .nobody
    private var window: [Entry] = []
    private var missStreak = 0
    private var lastFaceAt: TimeInterval?
    private var lastMatchAt: TimeInterval?

    public init(policy: StabilizerPolicy = StabilizerPolicy()) {
        self.policy = policy
    }

    public mutating func reset() {
        self = RecognitionStabilizer(policy: policy)
    }

    /// Returns the new decision when it changed, otherwise `nil`.
    @discardableResult
    public mutating func ingest(_ identity: FrameIdentity, at timestamp: TimeInterval) -> PresenceDecision? {
        let previous = decision
        switch identity {
        case .noFace:
            expireAbsence(at: timestamp)
        case .unusable:
            lastFaceAt = timestamp
            if decision == .nobody { decision = .unknownPerson }
            expireMatch(at: timestamp)
        case .unmatched:
            judge(nil, at: timestamp)
        case .matched(let profileID):
            judge(profileID, at: timestamp)
        }
        return decision == previous ? nil : decision
    }

    /// Applies the timeouts when no frame arrived, for example while the camera is interrupted.
    @discardableResult
    public mutating func advance(to timestamp: TimeInterval) -> PresenceDecision? {
        let previous = decision
        expireAbsence(at: timestamp)
        return decision == previous ? nil : decision
    }

    private mutating func expireAbsence(at timestamp: TimeInterval) {
        guard let lastFaceAt, timestamp - lastFaceAt >= policy.absenceTimeout else { return }
        reset()
    }

    private mutating func expireMatch(at timestamp: TimeInterval) {
        guard case .recognized = decision, let lastMatchAt, timestamp - lastMatchAt >= policy.matchTimeout else {
            return
        }
        decision = .unknownPerson
    }

    private mutating func judge(_ profileID: UUID?, at timestamp: TimeInterval) {
        lastFaceAt = timestamp
        window.append(Entry(time: timestamp, profileID: profileID))
        let maximumAge = policy.matchTimeout
        window.removeAll { timestamp - $0.time > maximumAge }
        window = Array(window.suffix(policy.windowSize))
        var counts: [UUID: Int] = [:]
        for case let id? in window.map(\.profileID) {
            counts[id, default: 0] += 1
        }

        var dropped: UUID?
        if case .recognized(let current) = decision {
            if profileID == current {
                missStreak = 0
                lastMatchAt = timestamp
            } else {
                missStreak += 1
            }
            let contested = counts.contains { $0.key != current && $0.value > policy.maximumCompetingMatches }
            if missStreak >= policy.missesToDrop || contested {
                decision = .unknownPerson
                dropped = current
            }
            expireMatch(at: timestamp)
        }
        if case .recognized = decision { return }

        // A profile dropped in this frame cannot win it back in the same frame on stale matches.
        let qualified = counts.filter { candidate in
            candidate.key != dropped
                && candidate.value >= policy.requiredMatches
                && counts.allSatisfy { $0.key == candidate.key || $0.value <= policy.maximumCompetingMatches }
        }
        if let winner = qualified.keys.first, qualified.count == 1 {
            decision = .recognized(winner)
            missStreak = 0
            lastMatchAt = timestamp
        } else {
            decision = .unknownPerson
        }
    }
}
