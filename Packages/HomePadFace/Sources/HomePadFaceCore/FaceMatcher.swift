import Foundation

/// Decision thresholds for one embedding model, as cosine similarity.
///
/// Similarity scales differ between models, so these numbers must be calibrated per model on
/// labeled pairs before a model is trusted. Raising `minimumSimilarity` and `minimumMargin`
/// trades more missed recognitions (the person stays a guest) for fewer wrong ones.
public struct MatchPolicy: Equatable, Sendable {
    /// A probe must be at least this similar to a profile to match it.
    public let minimumSimilarity: Float
    /// The best profile must beat the second best by at least this much.
    public let minimumMargin: Float
    /// At or above this similarity to another profile, an enrollment is treated as the same person.
    public let duplicateSimilarity: Float
    /// Samples of one enrollment must be at least this similar to an earlier sample.
    public let enrollmentConsistencySimilarity: Float

    public init(
        minimumSimilarity: Float,
        minimumMargin: Float,
        duplicateSimilarity: Float,
        enrollmentConsistencySimilarity: Float
    ) {
        self.minimumSimilarity = minimumSimilarity
        self.minimumMargin = minimumMargin
        self.duplicateSimilarity = duplicateSimilarity
        self.enrollmentConsistencySimilarity = enrollmentConsistencySimilarity
    }

    /// The same policy moved toward fewer missed recognitions or fewer wrong ones. Only the
    /// recognition bounds move. The enrollment guards stay as they are.
    public func adjusted(for strictness: MatchStrictness) -> MatchPolicy {
        MatchPolicy(
            minimumSimilarity: min(0.99, minimumSimilarity + strictness.similarityOffset),
            minimumMargin: minimumMargin + strictness.marginOffset,
            duplicateSimilarity: duplicateSimilarity,
            enrollmentConsistencySimilarity: enrollmentConsistencySimilarity
        )
    }

    /// Starting point for a margin-trained face model (ArcFace or MobileFaceNet style) that has
    /// not been calibrated yet. Deliberately strict.
    public static let conservativeDefault = MatchPolicy(
        minimumSimilarity: 0.6,
        minimumMargin: 0.1,
        duplicateSimilarity: 0.5,
        enrollmentConsistencySimilarity: 0.35
    )

    /// For the SFace model from the OpenCV Model Zoo. 0.363 is the cosine bound its publisher
    /// reports for "same person" with the publisher's own face detector and alignment. Here the
    /// landmarks come from a different detector, so treat it as a starting point. It was not
    /// calibrated on this household's faces, and the margin is an extra guard chosen here, not a
    /// published number.
    public static let sFace = MatchPolicy(
        minimumSimilarity: 0.363,
        minimumMargin: 0.05,
        duplicateSimilarity: 0.363,
        enrollmentConsistencySimilarity: 0.25
    )

    /// For generic image feature prints, which are not trained to separate identities. Aligned
    /// face crops of different people still score high, so every bound sits near 1. Uncalibrated
    /// and for development only.
    public static let featurePrintDevelopment = MatchPolicy(
        minimumSimilarity: 0.9,
        minimumMargin: 0.05,
        duplicateSimilarity: 0.88,
        enrollmentConsistencySimilarity: 0.75
    )
}

/// How readily a face is accepted as a match, relative to the model's own policy.
public enum MatchStrictness: String, CaseIterable, Sendable {
    case relaxed, standard, strict

    var similarityOffset: Float {
        switch self {
        case .relaxed: -0.04
        case .standard: 0
        case .strict: 0.08
        }
    }

    var marginOffset: Float {
        self == .strict ? 0.03 : 0
    }
}

/// Match policies keyed by embedding model ID, with a strict fallback for unknown models.
public struct MatchPolicyTable: Equatable, Sendable {
    public private(set) var policies: [String: MatchPolicy]
    public let fallback: MatchPolicy

    public init(policies: [String: MatchPolicy] = [:], fallback: MatchPolicy = .conservativeDefault) {
        self.policies = policies
        self.fallback = fallback
    }

    public mutating func register(_ policy: MatchPolicy, forModelID modelID: String) {
        policies[modelID] = policy
    }

    public func policy(forModelID modelID: String) -> MatchPolicy {
        policies[modelID] ?? fallback
    }

    public func adjusted(for strictness: MatchStrictness) -> MatchPolicyTable {
        MatchPolicyTable(
            policies: policies.mapValues { $0.adjusted(for: strictness) },
            fallback: fallback.adjusted(for: strictness)
        )
    }
}

public struct FaceMatchCandidate: Equatable, Sendable {
    public let profileID: UUID
    public let similarity: Float

    public init(profileID: UUID, similarity: Float) {
        self.profileID = profileID
        self.similarity = similarity
    }
}

public enum FaceMatchDecision: Equatable, Sendable {
    case match(UUID)
    /// The best profile is not similar enough.
    case belowThreshold
    /// The best profile is similar enough but too close to the runner-up.
    case ambiguous
    /// No template was made by the probe's model.
    case noComparableTemplates
}

public struct FaceMatchResult: Equatable, Sendable {
    public let best: FaceMatchCandidate?
    public let secondBest: FaceMatchCandidate?
    public let decision: FaceMatchDecision

    public var matchedProfileID: UUID? {
        if case .match(let id) = decision { id } else { nil }
    }
}

public struct FaceMatcher: Sendable {
    public let policies: MatchPolicyTable

    public init(policies: MatchPolicyTable = MatchPolicyTable()) {
        self.policies = policies
    }

    /// Ranks profiles by their best sample. Templates from another model are skipped.
    public func match(_ probe: FaceEmbedding, against templates: [FaceTemplate]) -> FaceMatchResult {
        var bestByProfile: [UUID: Float] = [:]
        for template in templates {
            guard let similarity = template.bestSimilarity(to: probe) else { continue }
            bestByProfile[template.profileID] = max(similarity, bestByProfile[template.profileID] ?? -1)
        }
        let ranked = bestByProfile
            .map { FaceMatchCandidate(profileID: $0.key, similarity: $0.value) }
            .sorted { ($0.similarity, $1.profileID.uuidString) > ($1.similarity, $0.profileID.uuidString) }
        guard let best = ranked.first else {
            return FaceMatchResult(best: nil, secondBest: nil, decision: .noComparableTemplates)
        }
        let secondBest = ranked.dropFirst().first
        let policy = policies.policy(forModelID: probe.modelID)
        let decision: FaceMatchDecision
        if best.similarity < policy.minimumSimilarity {
            decision = .belowThreshold
        } else if let secondBest, best.similarity - secondBest.similarity < policy.minimumMargin {
            decision = .ambiguous
        } else {
            decision = .match(best.profileID)
        }
        return FaceMatchResult(best: best, secondBest: secondBest, decision: decision)
    }
}
