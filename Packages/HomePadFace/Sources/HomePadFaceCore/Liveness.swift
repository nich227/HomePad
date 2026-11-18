import Foundation

public enum LivenessVerdict: String, Equatable, Sendable {
    case live
    case spoofSuspected
    case indeterminate
}

/// Thresholds for the depth relief test. The defaults are conservative guesses for a TrueDepth
/// camera at tabletop range and must be calibrated on the target device.
public struct DepthLivenessPolicy: Equatable, Sendable {
    public var minimumValidSamples: Int
    public var minimumValidFraction: Float
    /// Depth accuracy falls off outside this range, in meters, so no verdict is given there.
    public var distanceRange: ClosedRange<Float>
    /// At or below this plane residual the surface is flat: a photo or a screen.
    public var spoofMaximumResidual: Float
    public var liveMinimumResidual: Float
    public var liveMinimumRelief: Float

    public init(
        minimumValidSamples: Int = 40,
        minimumValidFraction: Float = 0.6,
        distanceRange: ClosedRange<Float> = 0.2...1.2,
        spoofMaximumResidual: Float = 0.003,
        liveMinimumResidual: Float = 0.006,
        liveMinimumRelief: Float = 0.008
    ) {
        self.minimumValidSamples = minimumValidSamples
        self.minimumValidFraction = minimumValidFraction
        self.distanceRange = distanceRange
        self.spoofMaximumResidual = spoofMaximumResidual
        self.liveMinimumResidual = liveMinimumResidual
        self.liveMinimumRelief = liveMinimumRelief
    }
}

/// Judges one frame of depth. It cannot tell a face from a mask or another shaped object: it
/// only separates flat surfaces from surfaces with face-like relief.
public struct LivenessEvaluator: Equatable, Sendable {
    public let policy: DepthLivenessPolicy

    public init(policy: DepthLivenessPolicy = DepthLivenessPolicy()) {
        self.policy = policy
    }

    public func evaluate(_ depth: FaceDepthStatistics?) -> LivenessVerdict {
        guard
            let depth,
            depth.validCount >= policy.minimumValidSamples,
            depth.validFraction >= policy.minimumValidFraction,
            policy.distanceRange.contains(depth.medianDepth)
        else { return .indeterminate }
        if depth.planeResidual <= policy.spoofMaximumResidual { return .spoofSuspected }
        if depth.planeResidual >= policy.liveMinimumResidual, depth.centerRelief >= policy.liveMinimumRelief {
            return .live
        }
        return .indeterminate
    }
}

/// Thresholds for the no-depth challenge: a blink or a smooth head turn seen across frames.
public struct ChallengeLivenessPolicy: Equatable, Sendable {
    /// Eyes count as closed below this fraction of the open baseline.
    public var closedRatio: Float
    /// Eyes count as open again at or above this fraction of the open baseline.
    public var reopenedRatio: Float
    public var openFramesForBaseline: Int
    public var maximumBlinkDuration: TimeInterval
    /// Yaw range, in radians, the head must cover within `sweepWindow`.
    public var minimumYawSweep: Double
    public var sweepWindow: TimeInterval
    public var minimumSweepFrames: Int
    /// A larger yaw change between two frames is a cut between images, not a head turn.
    public var maximumYawStep: Double
    /// How long a passed challenge stays valid.
    public var validity: TimeInterval

    public init(
        closedRatio: Float = 0.6,
        reopenedRatio: Float = 0.85,
        openFramesForBaseline: Int = 3,
        maximumBlinkDuration: TimeInterval = 0.8,
        minimumYawSweep: Double = 12 * .pi / 180,
        sweepWindow: TimeInterval = 4,
        minimumSweepFrames: Int = 4,
        maximumYawStep: Double = 15 * .pi / 180,
        validity: TimeInterval = 20
    ) {
        self.closedRatio = closedRatio
        self.reopenedRatio = reopenedRatio
        self.openFramesForBaseline = openFramesForBaseline
        self.maximumBlinkDuration = maximumBlinkDuration
        self.minimumYawSweep = minimumYawSweep
        self.sweepWindow = sweepWindow
        self.minimumSweepFrames = minimumSweepFrames
        self.maximumYawStep = maximumYawStep
        self.validity = validity
    }
}

/// Watches eye openness and yaw across frames for signs of a moving face. A replayed video
/// passes this test, which is why a passed challenge does not unlock by default.
public struct ChallengeLivenessTracker: Sendable {
    private struct YawSample: Sendable {
        let time: TimeInterval
        let yaw: Double
    }

    public let policy: ChallengeLivenessPolicy
    private var openBaseline: Float = 0
    private var openFrames = 0
    private var closedSince: TimeInterval?
    private var yawHistory: [YawSample] = []
    private var passedAt: TimeInterval?

    public init(policy: ChallengeLivenessPolicy = ChallengeLivenessPolicy()) {
        self.policy = policy
    }

    public mutating func reset() {
        self = ChallengeLivenessTracker(policy: policy)
    }

    public func hasPassed(at timestamp: TimeInterval) -> Bool {
        passedAt.map { timestamp - $0 <= policy.validity } ?? false
    }

    public mutating func observe(yaw: Double, eyeOpenness: Float?, at timestamp: TimeInterval) {
        if let eyeOpenness, eyeOpenness.isFinite, observeBlink(eyeOpenness, at: timestamp) {
            passedAt = timestamp
        }
        if yaw.isFinite, observeSweep(yaw, at: timestamp) {
            passedAt = timestamp
        }
    }

    private mutating func observeBlink(_ openness: Float, at timestamp: TimeInterval) -> Bool {
        if let closed = closedSince {
            if timestamp - closed > policy.maximumBlinkDuration {
                // Too long for a blink, so the baseline was wrong or the eyes are resting shut.
                closedSince = nil
                openBaseline = openness
                openFrames = 1
                return false
            }
            guard openness >= openBaseline * policy.reopenedRatio else { return false }
            closedSince = nil
            return true
        }
        if openFrames >= policy.openFramesForBaseline, openness < openBaseline * policy.closedRatio {
            closedSince = timestamp
            return false
        }
        openFrames += 1
        openBaseline = max(openBaseline, openness)
        return false
    }

    private mutating func observeSweep(_ yaw: Double, at timestamp: TimeInterval) -> Bool {
        if let last = yawHistory.last, abs(yaw - last.yaw) > policy.maximumYawStep {
            yawHistory.removeAll()
        }
        yawHistory.append(YawSample(time: timestamp, yaw: yaw))
        let window = policy.sweepWindow
        yawHistory.removeAll { timestamp - $0.time > window }
        let yaws = yawHistory.map(\.yaw)
        guard yawHistory.count >= policy.minimumSweepFrames, let low = yaws.min(), let high = yaws.max() else {
            return false
        }
        return high - low >= policy.minimumYawSweep
    }
}

public enum LivenessEvidence: String, Equatable, Sendable {
    /// Depth relief from a depth camera.
    case depth
    /// A blink or head turn seen by the color camera only.
    case challenge
    case none
}

/// What a recognized face is allowed to do.
public enum RecognitionGrant: String, Equatable, Sendable {
    /// Liveness is established. Maps to `HouseholdSession.faceRecognized`.
    case unlockPersonalContent
    /// The face matched but liveness is not established. Treat like a manual switch: personalize,
    /// keep personal content locked. Maps to `HouseholdSession.switchManually`.
    case personalizeOnly
    /// Treat the face as an unknown person.
    case deny
}

public struct LivenessAssessment: Equatable, Sendable {
    public let verdict: LivenessVerdict
    public let evidence: LivenessEvidence
    public let grant: RecognitionGrant

    public init(verdict: LivenessVerdict, evidence: LivenessEvidence, grant: RecognitionGrant) {
        self.verdict = verdict
        self.evidence = evidence
        self.grant = grant
    }
}

public struct LivenessPolicy: Equatable, Sendable {
    public var depth: DepthLivenessPolicy
    public var challenge: ChallengeLivenessPolicy
    public var liveFramesToConfirm: Int
    public var spoofFramesToRevoke: Int
    /// Depth evidence older than this no longer counts. `nil` keeps it for the whole visit.
    public var liveEvidenceMaximumAge: TimeInterval?
    /// Whether a face match without established liveness may personalize the hub. Personal
    /// content stays locked either way.
    public var indeterminateMayPersonalize: Bool
    /// Whether a passed blink or head-turn challenge counts as live when there is no depth.
    /// Off by default because a replayed video passes the challenge.
    public var passedChallengeMayUnlock: Bool

    public init(
        depth: DepthLivenessPolicy = DepthLivenessPolicy(),
        challenge: ChallengeLivenessPolicy = ChallengeLivenessPolicy(),
        liveFramesToConfirm: Int = 2,
        spoofFramesToRevoke: Int = 2,
        liveEvidenceMaximumAge: TimeInterval? = 30,
        indeterminateMayPersonalize: Bool = true,
        passedChallengeMayUnlock: Bool = false
    ) {
        self.depth = depth
        self.challenge = challenge
        self.liveFramesToConfirm = liveFramesToConfirm
        self.spoofFramesToRevoke = spoofFramesToRevoke
        self.liveEvidenceMaximumAge = liveEvidenceMaximumAge
        self.indeterminateMayPersonalize = indeterminateMayPersonalize
        self.passedChallengeMayUnlock = passedChallengeMayUnlock
    }
}

/// Accumulates liveness evidence for one person across frames. Reset it whenever the face in
/// front of the camera may belong to someone else, so evidence never carries over.
public struct LivenessTracker: Sendable {
    public let policy: LivenessPolicy
    private let evaluator: LivenessEvaluator
    private var challenge: ChallengeLivenessTracker
    private var liveStreak = 0
    private var spoofStreak = 0
    private var isLiveConfirmed = false
    private var isSpoofLatched = false
    private var lastLiveAt: TimeInterval?

    public init(policy: LivenessPolicy = LivenessPolicy()) {
        self.policy = policy
        self.evaluator = LivenessEvaluator(policy: policy.depth)
        self.challenge = ChallengeLivenessTracker(policy: policy.challenge)
    }

    public mutating func reset() {
        self = LivenessTracker(policy: policy)
    }

    @discardableResult
    public mutating func ingest(
        depth: FaceDepthStatistics?,
        yaw: Double,
        eyeOpenness: Float?,
        at timestamp: TimeInterval
    ) -> LivenessAssessment {
        challenge.observe(yaw: yaw, eyeOpenness: eyeOpenness, at: timestamp)
        switch evaluator.evaluate(depth) {
        case .live:
            spoofStreak = 0
            liveStreak += 1
            lastLiveAt = timestamp
            if liveStreak >= policy.liveFramesToConfirm {
                isLiveConfirmed = true
                isSpoofLatched = false
            }
        case .spoofSuspected:
            liveStreak = 0
            spoofStreak += 1
            if spoofStreak >= policy.spoofFramesToRevoke {
                isSpoofLatched = true
                isLiveConfirmed = false
            }
        case .indeterminate:
            break
        }
        return assessment(at: timestamp)
    }

    public func assessment(at timestamp: TimeInterval) -> LivenessAssessment {
        if isSpoofLatched {
            return LivenessAssessment(verdict: .spoofSuspected, evidence: .depth, grant: .deny)
        }
        if isLiveConfirmed, let lastLiveAt, policy.liveEvidenceMaximumAge.map({ timestamp - lastLiveAt <= $0 }) ?? true {
            return LivenessAssessment(verdict: .live, evidence: .depth, grant: .unlockPersonalContent)
        }
        let passedChallenge = challenge.hasPassed(at: timestamp)
        if passedChallenge, policy.passedChallengeMayUnlock {
            return LivenessAssessment(verdict: .live, evidence: .challenge, grant: .unlockPersonalContent)
        }
        return LivenessAssessment(
            verdict: .indeterminate,
            evidence: passedChallenge ? .challenge : .none,
            grant: policy.indeterminateMayPersonalize ? .personalizeOnly : .deny
        )
    }
}
