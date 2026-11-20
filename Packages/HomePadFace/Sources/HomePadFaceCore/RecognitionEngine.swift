import Foundation
import HomePadCore

public struct RecognitionEngineConfiguration: Equatable, Sendable {
    public var matchPolicies: MatchPolicyTable
    public var stabilizer: StabilizerPolicy
    public var liveness: LivenessPolicy
    public var proximity: ProximityPolicy
    /// Frames below this capture quality are not matched.
    public var minimumCaptureQuality: Float
    /// Frames with the head turned farther than this, in radians, are not matched.
    public var maximumYaw: Double
    public var maximumPitch: Double

    public init(
        matchPolicies: MatchPolicyTable = MatchPolicyTable(),
        stabilizer: StabilizerPolicy = StabilizerPolicy(),
        liveness: LivenessPolicy = LivenessPolicy(),
        proximity: ProximityPolicy = .standard,
        minimumCaptureQuality: Float = 0.15,
        maximumYaw: Double = 40 * .pi / 180,
        maximumPitch: Double = 35 * .pi / 180
    ) {
        self.matchPolicies = matchPolicies
        self.stabilizer = stabilizer
        self.liveness = liveness
        self.proximity = proximity
        self.minimumCaptureQuality = minimumCaptureQuality
        self.maximumYaw = maximumYaw
        self.maximumPitch = maximumPitch
    }
}

/// The steady answer to "who is in front of the hub, and what may they see".
public enum RecognitionOutcome: Equatable, Sendable {
    case nobody
    /// Someone is there who is not enrolled, could not be told apart, or looks like a spoof.
    case unknownPerson
    /// An enrolled member whose liveness is not established. Personalize, keep personal content
    /// locked.
    case personalized(UUID)
    /// An enrolled member with established liveness. Personal content may show.
    case unlocked(UUID)

    public var profileID: UUID? {
        switch self {
        case .nobody, .unknownPerson: nil
        case .personalized(let id), .unlocked(let id): id
        }
    }
}

public struct RecognitionUpdate: Equatable, Sendable {
    public let outcome: RecognitionOutcome
    public let proximity: Proximity
    /// Whether a face was in the latest frame. The outcome lags behind this by design.
    public let isFacePresent: Bool
    /// Liveness of the recognized member, when there is one.
    public let liveness: LivenessAssessment?
    /// True when this frame matched a different enrolled member than the one being recognized.
    /// Anything that vouched for the recognized member, such as a device biometric
    /// confirmation, no longer counts, even though the outcome may stay the same.
    public let matchedAnotherMember: Bool
    /// True when the outcome is `unknownPerson` only because the face in view cannot be judged,
    /// or has not been judged enough to say it is someone else. It may still be the member who
    /// was recognized a moment ago, so the session lets that member linger. False when judged
    /// frames say the person is a stranger, and when a recognized member fails the liveness
    /// test.
    public let isFaceUnreadable: Bool
    /// Whether the session needs to hear about this update: the outcome, proximity, or
    /// `isFaceUnreadable` differs from the previous update, or `matchedAnotherMember` is set.
    public let didChange: Bool

    public init(
        outcome: RecognitionOutcome,
        proximity: Proximity,
        isFacePresent: Bool,
        liveness: LivenessAssessment?,
        matchedAnotherMember: Bool = false,
        isFaceUnreadable: Bool = false,
        didChange: Bool
    ) {
        self.outcome = outcome
        self.proximity = proximity
        self.isFacePresent = isFacePresent
        self.liveness = liveness
        self.matchedAnotherMember = matchedAnotherMember
        self.isFaceUnreadable = isFaceUnreadable
        self.didChange = didChange
    }

    public static let idle = RecognitionUpdate(
        outcome: .nobody,
        proximity: .far,
        isFacePresent: false,
        liveness: nil,
        didChange: false
    )
}

/// Combines matching, stabilizing, liveness, and proximity for a stream of analyzed frames.
public struct RecognitionEngine: Sendable {
    public let configuration: RecognitionEngineConfiguration
    public private(set) var latest: RecognitionUpdate = .idle
    private let matcher: FaceMatcher
    private var stabilizer: RecognitionStabilizer
    private var liveness: LivenessTracker
    private var proximity: ProximityEstimator
    /// The profile the liveness evidence belongs to. Evidence gathered on frames that matched one
    /// member must never vouch for another, so it is collected per matched profile.
    private var livenessSubject: UUID?

    public init(configuration: RecognitionEngineConfiguration = RecognitionEngineConfiguration()) {
        self.configuration = configuration
        self.matcher = FaceMatcher(policies: configuration.matchPolicies)
        self.stabilizer = RecognitionStabilizer(policy: configuration.stabilizer)
        self.liveness = LivenessTracker(policy: configuration.liveness)
        self.proximity = ProximityEstimator(policy: configuration.proximity)
    }

    /// Forgets everyone, for example when the camera stops.
    @discardableResult
    public mutating func reset() -> RecognitionUpdate {
        stabilizer.reset()
        clearPresence()
        return publish(isFacePresent: false, at: 0)
    }

    /// Applies timeouts when no frame arrived.
    @discardableResult
    public mutating func advance(to timestamp: TimeInterval) -> RecognitionUpdate {
        stabilizer.advance(to: timestamp)
        if stabilizer.decision == .nobody { clearPresence() }
        return publish(isFacePresent: false, at: timestamp)
    }

    @discardableResult
    public mutating func process(_ frame: FaceFrameObservation, templates: [FaceTemplate]) -> RecognitionUpdate {
        guard let face = frame.primary else {
            stabilizer.ingest(.noFace, at: frame.timestamp)
            if stabilizer.decision == .nobody { clearPresence() }
            return publish(isFacePresent: false, at: frame.timestamp)
        }
        proximity.update(distance: face.distance?.meters)
        let identity = identity(of: face, templates: templates)
        var matchedAnotherMember = false
        if case .matched(let profileID) = identity {
            if case .recognized(let recognized) = stabilizer.decision, recognized != profileID {
                matchedAnotherMember = true
            }
            if profileID != livenessSubject {
                liveness.reset()
                livenessSubject = profileID
            }
            liveness.ingest(depth: face.depth, yaw: face.pose.yaw, eyeOpenness: face.eyeOpenness, at: frame.timestamp)
        }
        stabilizer.ingest(identity, at: frame.timestamp)
        return publish(isFacePresent: true, at: frame.timestamp, matchedAnotherMember: matchedAnotherMember)
    }

    private func identity(of face: FaceObservationSample, templates: [FaceTemplate]) -> FrameIdentity {
        guard
            let embedding = face.embedding,
            face.captureQuality >= configuration.minimumCaptureQuality,
            abs(face.pose.yaw) <= configuration.maximumYaw,
            abs(face.pose.pitch) <= configuration.maximumPitch
        else { return .unusable }
        return matcher.match(embedding, against: templates).matchedProfileID.map(FrameIdentity.matched) ?? .unmatched
    }

    private mutating func clearPresence() {
        liveness.reset()
        livenessSubject = nil
        proximity.reset()
    }

    private mutating func publish(
        isFacePresent: Bool,
        at timestamp: TimeInterval,
        matchedAnotherMember: Bool = false
    ) -> RecognitionUpdate {
        var assessment: LivenessAssessment?
        var isFaceUnreadable = false
        let outcome: RecognitionOutcome
        switch stabilizer.decision {
        case .nobody:
            outcome = .nobody
        case .unknownPerson:
            outcome = .unknownPerson
            isFaceUnreadable = !stabilizer.hasJudgedStranger
        case .recognized(let profileID):
            // The stabilizer can hold a member the liveness evidence is not about (after a stray
            // match of someone else). Then there is no evidence, which is judged as such.
            let current = profileID == livenessSubject
                ? liveness.assessment(at: timestamp)
                : LivenessTracker(policy: configuration.liveness).assessment(at: timestamp)
            assessment = current
            switch current.grant {
            case .unlockPersonalContent: outcome = .unlocked(profileID)
            case .personalizeOnly: outcome = .personalized(profileID)
            case .deny: outcome = .unknownPerson
            }
        }
        latest = RecognitionUpdate(
            outcome: outcome,
            proximity: proximity.proximity,
            isFacePresent: isFacePresent,
            liveness: assessment,
            matchedAnotherMember: matchedAnotherMember,
            isFaceUnreadable: isFaceUnreadable,
            didChange: outcome != latest.outcome || proximity.proximity != latest.proximity || matchedAnotherMember
                || isFaceUnreadable != latest.isFaceUnreadable
        )
        return latest
    }
}

/// Applies recognition outcomes to the household session. The session decides what each report
/// means for the audience: a member the camera can no longer see or judge lingers, and one who
/// is replaced by a judged stranger or another member signs out.
///
/// | Camera | Report to the session |
/// |---|---|
/// | Nobody in view past the lock delay | `presenceLost` |
/// | A face that cannot be judged, or not judged enough yet | `faceUnreadable` |
/// | A judged face that is not a member, or a member's face that fails liveness | `unknownFacePresent` |
/// | A member, liveness not established | `faceMatchedWithoutLiveness` |
/// | A member, live | `faceRecognized` |
@MainActor
public final class HouseholdSessionDriver {
    public init() {}

    public func apply(_ update: RecognitionUpdate, to session: HouseholdSession, at date: Date) {
        // A member removed while their template was still loaded is a stranger to the session.
        let isMember = update.outcome.profileID.map { id in session.profiles.contains { $0.id == id } } ?? false
        switch update.outcome {
        case .unlocked(let profileID) where isMember:
            session.faceRecognized(profileID: profileID, proximity: update.proximity, at: date)
        case .personalized(let profileID) where isMember:
            // The session keeps a device biometric confirmation across repeated matches of the
            // same member. A frame that matched someone else ends it: the fingerprint vouched for
            // whoever stood there before. The member does not sign out over one such frame.
            if update.matchedAnotherMember {
                session.dropDeviceBiometricConfirmation()
            }
            session.faceMatchedWithoutLiveness(profileID: profileID, proximity: update.proximity, at: date)
        case .unlocked, .personalized, .unknownPerson:
            if update.isFaceUnreadable {
                session.faceUnreadable(proximity: update.proximity, at: date)
            } else {
                session.unknownFacePresent(proximity: update.proximity, at: date)
            }
        case .nobody:
            session.presenceLost(at: date)
        }
    }
}
