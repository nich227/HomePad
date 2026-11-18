import Foundation

public struct EnrollmentPolicy: Equatable, Sendable {
    /// Buckets to fill. `center` is captured first because it anchors the identity checks.
    public var requiredBuckets: [HeadPoseBucket]
    public var samplesPerBucket: Int
    /// Capture quality needed for a frontal sample, in 0...1.
    public var minimumCenterQuality: Float
    /// Turned faces score lower, so they get their own bound.
    public var minimumTurnedQuality: Float
    /// Smallest usable face, as face box height over the frame's shorter side.
    public var minimumSizeFraction: Double
    /// Accept samples whose liveness could not be established. Meant for cameras without depth.
    public var allowsIndeterminateLiveness: Bool
    /// Consecutive samples that match another profile before the session is blocked.
    public var duplicateSamplesToBlock: Int
    public var bucketing: HeadPoseBucketing

    public init(
        requiredBuckets: [HeadPoseBucket] = HeadPoseBucket.allCases,
        samplesPerBucket: Int = 2,
        minimumCenterQuality: Float = 0.3,
        minimumTurnedQuality: Float = 0.15,
        minimumSizeFraction: Double = 0.2,
        allowsIndeterminateLiveness: Bool = false,
        duplicateSamplesToBlock: Int = 3,
        bucketing: HeadPoseBucketing = HeadPoseBucketing()
    ) {
        self.requiredBuckets = requiredBuckets.contains(.center) ? requiredBuckets : [.center] + requiredBuckets
        self.samplesPerBucket = max(1, samplesPerBucket)
        self.minimumCenterQuality = minimumCenterQuality
        self.minimumTurnedQuality = minimumTurnedQuality
        self.minimumSizeFraction = minimumSizeFraction
        self.allowsIndeterminateLiveness = allowsIndeterminateLiveness
        self.duplicateSamplesToBlock = max(1, duplicateSamplesToBlock)
        self.bucketing = bucketing
    }
}

public struct EnrollmentCandidate: Equatable, Sendable {
    public let pose: HeadPose
    public let captureQuality: Float
    public let embedding: FaceEmbedding
    public let liveness: LivenessVerdict

    public init(pose: HeadPose, captureQuality: Float, embedding: FaceEmbedding, liveness: LivenessVerdict) {
        self.pose = pose
        self.captureQuality = captureQuality
        self.embedding = embedding
        self.liveness = liveness
    }
}

public enum EnrollmentRejection: Error, Equatable, Sendable {
    case sessionFinished
    /// The embedding was made by a different model than the session was started for.
    case modelMismatch
    case spoofSuspected
    case livenessUnverified
    /// The head is between poses, tilted sideways, or turned too far.
    case poseNotUsable
    /// The pose is usable but that bucket is not open. `expected` is the one to prompt for.
    case wrongPose(expected: HeadPoseBucket)
    case lowQuality
    /// The face matches another household member's template.
    case duplicateOfProfile(UUID)
    /// The face does not look like the person who started this enrollment.
    case inconsistentIdentity
}

public enum EnrollmentState: Equatable, Sendable {
    /// Still collecting. `next` is the pose to prompt for.
    case collecting(next: HeadPoseBucket)
    case complete
    case blockedByDuplicate(UUID)
}

public enum EnrollmentFeedback: Equatable, Sendable {
    case noFace
    case multipleFaces
    case tooFar
    case captured(HeadPoseBucket)
    case rejected(EnrollmentRejection)
    case finished
}

/// Collects face samples for one household member across head poses and turns them into a
/// template. It keeps embeddings only, never images.
public struct EnrollmentSession: Sendable {
    public let profileID: UUID
    public let modelID: String
    public let policy: EnrollmentPolicy
    public private(set) var samples: [FaceTemplate.Sample] = []
    public private(set) var state: EnrollmentState = .collecting(next: .center)
    private let matchPolicy: MatchPolicy
    private let otherTemplates: [FaceTemplate]
    private var duplicateStreak = 0

    /// - Parameters:
    ///   - existingTemplates: every stored template. The member's own template is ignored so a
    ///     face can be enrolled again. Templates from other models cannot be compared and are
    ///     skipped, so the duplicate guard only covers templates made by `modelID`.
    public init(
        profileID: UUID,
        modelID: String,
        matchPolicy: MatchPolicy,
        existingTemplates: [FaceTemplate],
        policy: EnrollmentPolicy = EnrollmentPolicy()
    ) {
        self.profileID = profileID
        self.modelID = modelID
        self.matchPolicy = matchPolicy
        self.policy = policy
        self.otherTemplates = existingTemplates.filter { $0.profileID != profileID }
    }

    // MARK: Progress

    public func capturedCount(in bucket: HeadPoseBucket) -> Int {
        samples.count { $0.bucket == bucket }
    }

    public func isComplete(_ bucket: HeadPoseBucket) -> Bool {
        capturedCount(in: bucket) >= policy.samplesPerBucket
    }

    /// 0...1 for one bucket.
    public func progress(in bucket: HeadPoseBucket) -> Double {
        min(1, Double(capturedCount(in: bucket)) / Double(policy.samplesPerBucket))
    }

    /// 0...1 across all required buckets.
    public var progress: Double {
        policy.requiredBuckets.reduce(0) { $0 + progress(in: $1) } / Double(policy.requiredBuckets.count)
    }

    /// The pose to prompt for next, or `nil` when every bucket is full.
    public var nextBucket: HeadPoseBucket? {
        if !isComplete(.center) { return .center }
        return policy.requiredBuckets.first { !isComplete($0) }
    }

    // MARK: Samples

    /// Checks one analyzed frame and adds its face as a sample when it qualifies.
    public mutating func ingest(_ frame: FaceFrameObservation, liveness: LivenessVerdict) -> EnrollmentFeedback {
        if state == .complete { return .finished }
        guard let face = frame.primary else { return .noFace }
        if frame.prominentFaceCount > 1 { return .multipleFaces }
        if face.sizeFraction < policy.minimumSizeFraction { return .tooFar }
        guard let embedding = face.embedding else { return .rejected(.lowQuality) }
        let candidate = EnrollmentCandidate(
            pose: face.pose,
            captureQuality: face.captureQuality,
            embedding: embedding,
            liveness: liveness
        )
        switch add(candidate) {
        case .success(let bucket): return state == .complete ? .finished : .captured(bucket)
        case .failure(let rejection): return .rejected(rejection)
        }
    }

    @discardableResult
    public mutating func add(_ candidate: EnrollmentCandidate) -> Result<HeadPoseBucket, EnrollmentRejection> {
        let expected: HeadPoseBucket
        switch state {
        case .complete: return .failure(.sessionFinished)
        case .blockedByDuplicate(let other): return .failure(.duplicateOfProfile(other))
        case .collecting(let next): expected = next
        }
        guard candidate.embedding.modelID == modelID else { return .failure(.modelMismatch) }
        switch candidate.liveness {
        case .spoofSuspected: return .failure(.spoofSuspected)
        case .indeterminate where !policy.allowsIndeterminateLiveness: return .failure(.livenessUnverified)
        default: break
        }
        guard let bucket = policy.bucketing.bucket(for: candidate.pose) else { return .failure(.poseNotUsable) }
        let isOpen = policy.requiredBuckets.contains(bucket) && !isComplete(bucket) && (bucket == .center || isComplete(.center))
        guard isOpen else { return .failure(.wrongPose(expected: expected)) }
        let minimumQuality = bucket == .center ? policy.minimumCenterQuality : policy.minimumTurnedQuality
        guard candidate.captureQuality >= minimumQuality else { return .failure(.lowQuality) }

        if let duplicate = duplicateProfile(for: candidate.embedding) {
            duplicateStreak += 1
            if duplicateStreak >= policy.duplicateSamplesToBlock {
                state = .blockedByDuplicate(duplicate)
            }
            return .failure(.duplicateOfProfile(duplicate))
        }
        duplicateStreak = 0

        let similarities = samples.compactMap { $0.embedding.similarity(to: candidate.embedding) }
        if !samples.isEmpty, (similarities.max() ?? -1) < matchPolicy.enrollmentConsistencySimilarity {
            return .failure(.inconsistentIdentity)
        }

        samples.append(FaceTemplate.Sample(bucket: bucket, embedding: candidate.embedding))
        state = nextBucket.map { .collecting(next: $0) } ?? .complete
        return .success(bucket)
    }

    /// The finished template, or `nil` while samples are still missing.
    public func makeTemplate(createdAt: Date) -> FaceTemplate? {
        guard state == .complete else { return nil }
        return try? FaceTemplate(profileID: profileID, samples: samples, createdAt: createdAt)
    }

    private func duplicateProfile(for embedding: FaceEmbedding) -> UUID? {
        otherTemplates
            .compactMap { template in template.bestSimilarity(to: embedding).map { (template.profileID, $0) } }
            .filter { $0.1 >= matchPolicy.duplicateSimilarity }
            .max { $0.1 < $1.1 }?
            .0
    }
}

/// A problem to tell the person about during enrollment.
public enum EnrollmentIssue: Equatable, Sendable {
    case noFace
    case multipleFaces
    case tooFar
    /// Blur or poor lighting.
    case poorQuality
    /// The camera could not confirm a real face.
    case livenessNotConfirmed
    /// The face does not look like the person who started.
    case differentPerson
}

/// Steadies per-frame feedback so the on-screen hint does not flicker. An issue shows only
/// after it repeats, and clears as soon as a frame is fine.
public struct EnrollmentGuidance: Equatable, Sendable {
    public let framesToShow: Int
    public private(set) var issue: EnrollmentIssue?
    private var candidate: EnrollmentIssue?
    private var streak = 0

    public init(framesToShow: Int = 3) {
        self.framesToShow = max(1, framesToShow)
    }

    public static func issue(for feedback: EnrollmentFeedback) -> EnrollmentIssue? {
        switch feedback {
        case .noFace: .noFace
        case .multipleFaces: .multipleFaces
        case .tooFar: .tooFar
        case .rejected(.lowQuality): .poorQuality
        case .rejected(.spoofSuspected), .rejected(.livenessUnverified): .livenessNotConfirmed
        case .rejected(.inconsistentIdentity): .differentPerson
        // Pose prompts, the duplicate block, and the finished state have their own screens.
        case .captured, .finished, .rejected: nil
        }
    }

    public mutating func record(_ feedback: EnrollmentFeedback) {
        guard let next = Self.issue(for: feedback) else {
            issue = nil
            candidate = nil
            streak = 0
            return
        }
        streak = next == candidate ? streak + 1 : 1
        candidate = next
        if streak >= framesToShow {
            issue = next
        }
    }
}
