import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct EnrollmentSessionTests {
    private let alice = UUID()
    private let bob = UUID()
    private let matchPolicy = MatchPolicy(
        minimumSimilarity: 0.8,
        minimumMargin: 0.1,
        duplicateSimilarity: 0.7,
        enrollmentConsistencySimilarity: 0.5
    )
    private let poses: [HeadPoseBucket: HeadPose] = [
        .center: .frontal,
        .left: pose(yaw: 25),
        .right: pose(yaw: -25),
        .up: pose(pitch: 20),
        .down: pose(pitch: -20),
    ]

    private func session(existing: [FaceTemplate] = [], policy: EnrollmentPolicy = EnrollmentPolicy()) -> EnrollmentSession {
        EnrollmentSession(profileID: alice, modelID: testModelID, matchPolicy: matchPolicy, existingTemplates: existing, policy: policy)
    }

    private func candidate(
        _ degrees: Double = 0,
        _ bucket: HeadPoseBucket = .center,
        quality: Float = 0.6,
        liveness: LivenessVerdict = .live,
        model: String = testModelID,
        dimension: Int = 4
    ) throws -> EnrollmentCandidate {
        EnrollmentCandidate(
            pose: poses[bucket] ?? .frontal,
            captureQuality: quality,
            embedding: try vector(degrees, model: model, dimension: dimension),
            liveness: liveness
        )
    }

    private func fillCenter(_ session: inout EnrollmentSession) throws {
        #expect(session.add(try candidate(0)) == .success(.center))
        #expect(session.add(try candidate(2)) == .success(.center))
    }

    @Test func add_whenFrontalSampleQualifies_thenAcceptedAndProgressAdvances() throws {
        var session = session()
        #expect(session.nextBucket == .center)
        #expect(session.add(try candidate()) == .success(.center))
        #expect(session.capturedCount(in: .center) == 1)
        #expect(session.progress(in: .center) == 0.5)
        #expect(abs(session.progress - 0.1) < 1e-9)
        #expect(session.state == .collecting(next: .center))
    }

    @Test func add_whenEmbeddingFromAnotherModel_thenModelMismatch() throws {
        var session = session()
        #expect(session.add(try candidate(model: "other.model")) == .failure(.modelMismatch))
    }

    @Test func add_whenSpoofSuspected_thenRejected() throws {
        var session = session()
        #expect(session.add(try candidate(liveness: .spoofSuspected)) == .failure(.spoofSuspected))
        #expect(session.samples.isEmpty)
    }

    @Test func add_whenLivenessIndeterminate_thenRejectedUnlessPolicyAllows() throws {
        var strict = session()
        #expect(strict.add(try candidate(liveness: .indeterminate)) == .failure(.livenessUnverified))
        var lenient = session(policy: EnrollmentPolicy(allowsIndeterminateLiveness: true))
        #expect(lenient.add(try candidate(liveness: .indeterminate)) == .success(.center))
    }

    @Test func add_whenPoseBetweenBuckets_thenPoseNotUsable() throws {
        var session = session()
        let between = EnrollmentCandidate(pose: pose(yaw: 12.5), captureQuality: 0.6, embedding: try vector(0), liveness: .live)
        #expect(session.add(between) == .failure(.poseNotUsable))
    }

    @Test func add_whenTurnedBeforeCenterIsCaptured_thenWrongPoseExpectingCenter() throws {
        var session = session()
        #expect(session.add(try candidate(0, .left)) == .failure(.wrongPose(expected: .center)))
    }

    @Test func add_whenBucketAlreadyFull_thenWrongPoseExpectingNextBucket() throws {
        var session = session()
        try fillCenter(&session)
        #expect(session.isComplete(.center))
        #expect(session.add(try candidate(1)) == .failure(.wrongPose(expected: .left)))
    }

    @Test func add_whenBucketNotRequired_thenWrongPose() throws {
        var session = session(policy: EnrollmentPolicy(requiredBuckets: [.center, .left]))
        try fillCenter(&session)
        #expect(session.add(try candidate(0, .up)) == .failure(.wrongPose(expected: .left)))
    }

    @Test func add_whenQualityBelowBucketMinimum_thenLowQuality() throws {
        var session = session()
        #expect(session.add(try candidate(quality: 0.2)) == .failure(.lowQuality))
        try fillCenter(&session)
        #expect(session.add(try candidate(0, .left, quality: 0.1)) == .failure(.lowQuality))
        #expect(session.add(try candidate(0, .left, quality: 0.2)) == .success(.left))
    }

    @Test func add_whenFaceMatchesAnotherProfile_thenDuplicateAndBlocksAfterThreeInARow() throws {
        var session = session(existing: [try template(bob, degrees: [0])])
        #expect(session.add(try candidate(10)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.add(try candidate(12)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.state == .collecting(next: .center))
        #expect(session.add(try candidate(14)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.state == .blockedByDuplicate(bob))
        #expect(session.add(try candidate(170)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.samples.isEmpty)
        #expect(session.makeTemplate(createdAt: Date()) == nil)
    }

    @Test func add_whenDuplicateSamplesAreNotConsecutive_thenSessionStaysOpen() throws {
        var session = session(existing: [try template(bob, degrees: [0])])
        #expect(session.add(try candidate(10)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.add(try candidate(10)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.add(try candidate(100)) == .success(.center))
        #expect(session.add(try candidate(10)) == .failure(.duplicateOfProfile(bob)))
        #expect(session.state == .collecting(next: .center))
    }

    @Test func add_whenSeveralOtherProfilesMatch_thenReportsTheClosest() throws {
        let carol = UUID()
        var session = session(existing: [try template(bob, degrees: [30]), try template(carol, degrees: [5])])
        #expect(session.add(try candidate(0)) == .failure(.duplicateOfProfile(carol)))
    }

    @Test func add_whenOnlyOwnOrOtherModelTemplatesMatch_thenNotADuplicate() throws {
        var session = session(existing: [
            try template(alice, degrees: [0]),
            try template(bob, degrees: [0], model: "other.model"),
        ])
        #expect(session.add(try candidate(0)) == .success(.center))
    }

    @Test func add_whenFaceUnlikeEarlierSamples_thenInconsistentIdentity() throws {
        var session = session()
        #expect(session.add(try candidate(0)) == .success(.center))
        #expect(session.add(try candidate(90)) == .failure(.inconsistentIdentity))
        #expect(session.add(try candidate(50)) == .success(.center))
    }

    @Test func add_whenDimensionDiffersFromEarlierSamples_thenInconsistentIdentity() throws {
        var session = session()
        #expect(session.add(try candidate(0)) == .success(.center))
        #expect(session.add(try candidate(0, dimension: 8)) == .failure(.inconsistentIdentity))
    }

    @Test func add_whenEveryBucketIsFull_thenCompleteAndYieldsTemplate() throws {
        var session = session()
        try fillCenter(&session)
        for bucket in [HeadPoseBucket.right, .left, .down, .up] {
            #expect(session.nextBucket != nil)
            #expect(session.add(try candidate(5, bucket)) == .success(bucket))
            #expect(session.add(try candidate(6, bucket)) == .success(bucket))
        }
        #expect(session.state == .complete)
        #expect(session.nextBucket == nil)
        #expect(session.progress == 1)
        let created = Date(timeIntervalSince1970: 42)
        let made = try #require(session.makeTemplate(createdAt: created))
        #expect(made.profileID == alice)
        #expect(made.modelID == testModelID)
        #expect(made.createdAt == created)
        #expect(made.samples.count == 10)
        for bucket in HeadPoseBucket.allCases {
            #expect(made.sampleCount(in: bucket) == 2)
        }
        #expect(session.add(try candidate(0)) == .failure(.sessionFinished))
        #expect(session.ingest(try frame(at: 0, degrees: 0), liveness: .live) == .finished)
    }

    @Test func nextBucket_whenCenterDone_thenFollowsRequiredOrder() throws {
        var session = session()
        try fillCenter(&session)
        #expect(session.nextBucket == .left)
        #expect(session.state == .collecting(next: .left))
        _ = session.add(try candidate(0, .left))
        _ = session.add(try candidate(0, .left))
        #expect(session.nextBucket == .right)
    }

    @Test func makeTemplate_whenIncomplete_thenNil() throws {
        var session = session()
        try fillCenter(&session)
        #expect(session.makeTemplate(createdAt: Date()) == nil)
    }

    @Test func ingest_whenFrameHasNoUsableFace_thenExplainsWhy() throws {
        var session = session()
        #expect(session.ingest(.empty(at: 0), liveness: .live) == .noFace)
        #expect(session.ingest(try frame(at: 0, degrees: 0, faces: 2), liveness: .live) == .multipleFaces)
        #expect(session.ingest(try frame(at: 0, degrees: 0, size: 0.1), liveness: .live) == .tooFar)
        #expect(session.ingest(try frame(at: 0, degrees: nil), liveness: .live) == .rejected(.lowQuality))
        #expect(session.ingest(try frame(at: 0, degrees: 0), liveness: .spoofSuspected) == .rejected(.spoofSuspected))
        #expect(session.samples.isEmpty)
    }

    @Test func ingest_whenFaceQualifies_thenCapturedAndFinishedOnLastSample() throws {
        var session = session(policy: EnrollmentPolicy(requiredBuckets: [.center], samplesPerBucket: 2))
        #expect(session.ingest(try frame(at: 0, degrees: 0), liveness: .live) == .captured(.center))
        #expect(session.ingest(try frame(at: 1, degrees: 1), liveness: .live) == .finished)
        #expect(session.state == .complete)
    }

    @Test func policy_whenValuesOutOfRange_thenClamped() {
        let policy = EnrollmentPolicy(requiredBuckets: [.left], samplesPerBucket: 0, duplicateSamplesToBlock: 0)
        #expect(policy.requiredBuckets == [.center, .left])
        #expect(policy.samplesPerBucket == 1)
        #expect(policy.duplicateSamplesToBlock == 1)
    }
}

@Suite struct EnrollmentGuidanceTests {
    @Test func record_whenIssueRepeatsThreeFrames_thenShown() {
        var guidance = EnrollmentGuidance()
        guidance.record(.noFace)
        guidance.record(.noFace)
        #expect(guidance.issue == nil)
        guidance.record(.noFace)
        #expect(guidance.issue == .noFace)
    }

    @Test func record_whenIssueChangesBeforeRepeating_thenPreviousOneStays() {
        var guidance = EnrollmentGuidance(framesToShow: 2)
        guidance.record(.tooFar)
        guidance.record(.tooFar)
        guidance.record(.multipleFaces)
        #expect(guidance.issue == .tooFar)
        guidance.record(.multipleFaces)
        #expect(guidance.issue == .multipleFaces)
    }

    @Test func record_whenFrameIsFine_thenIssueClearsAtOnce() {
        var guidance = EnrollmentGuidance(framesToShow: 0)
        #expect(guidance.framesToShow == 1)
        guidance.record(.rejected(.lowQuality))
        #expect(guidance.issue == .poorQuality)
        guidance.record(.captured(.center))
        #expect(guidance.issue == nil)
        guidance.record(.rejected(.lowQuality))
        #expect(guidance.issue == .poorQuality)
    }

    @Test func issue_whenFeedbackGiven_thenMapsToWhatThePersonCanFix() {
        #expect(EnrollmentGuidance.issue(for: .noFace) == .noFace)
        #expect(EnrollmentGuidance.issue(for: .multipleFaces) == .multipleFaces)
        #expect(EnrollmentGuidance.issue(for: .tooFar) == .tooFar)
        #expect(EnrollmentGuidance.issue(for: .rejected(.lowQuality)) == .poorQuality)
        #expect(EnrollmentGuidance.issue(for: .rejected(.spoofSuspected)) == .livenessNotConfirmed)
        #expect(EnrollmentGuidance.issue(for: .rejected(.livenessUnverified)) == .livenessNotConfirmed)
        #expect(EnrollmentGuidance.issue(for: .rejected(.inconsistentIdentity)) == .differentPerson)
        #expect(EnrollmentGuidance.issue(for: .rejected(.poseNotUsable)) == nil)
        #expect(EnrollmentGuidance.issue(for: .rejected(.wrongPose(expected: .left))) == nil)
        #expect(EnrollmentGuidance.issue(for: .rejected(.duplicateOfProfile(UUID()))) == nil)
        #expect(EnrollmentGuidance.issue(for: .captured(.up)) == nil)
        #expect(EnrollmentGuidance.issue(for: .finished) == nil)
    }
}

@Suite struct CaptureFormatSelectorTests {
    private let selector = CaptureFormatSelector()
    private let formats = [
        CaptureFormatCandidate(width: 640, height: 480, maximumFrameRate: 30, supportsDepth: true),
        CaptureFormatCandidate(width: 1920, height: 1080, maximumFrameRate: 30, supportsDepth: false),
        CaptureFormatCandidate(width: 1280, height: 720, maximumFrameRate: 30, supportsDepth: false),
        CaptureFormatCandidate(width: 1280, height: 720, maximumFrameRate: 30, supportsDepth: true),
        CaptureFormatCandidate(width: 3840, height: 2160, maximumFrameRate: 10, supportsDepth: true),
    ]

    @Test func select_whenDepthPreferred_thenSmallestDepthFormatAtLeastTargetWidth() {
        #expect(selector.select(from: formats, prefersDepth: true) == 3)
    }

    @Test func select_whenDepthNotPreferred_thenSmallestFormatAtLeastTargetWidth() {
        #expect(selector.select(from: formats, prefersDepth: false) == 2)
    }

    @Test func select_whenNoFormatReachesTargetWidth_thenWidestAvailable() {
        let small = [
            CaptureFormatCandidate(width: 352, height: 288, maximumFrameRate: 30, supportsDepth: false),
            CaptureFormatCandidate(width: 640, height: 480, maximumFrameRate: 30, supportsDepth: false),
        ]
        #expect(selector.select(from: small, prefersDepth: false) == 1)
    }

    @Test func select_whenDepthPreferredButNoFormatHasIt_thenFallsBackToAnyFormat() {
        #expect(selector.select(from: Array(formats[1...2]), prefersDepth: true) == 1)
    }

    @Test func select_whenNoFormatIsFastEnough_thenNil() {
        #expect(selector.select(from: [formats[4]], prefersDepth: true) == nil)
        #expect(selector.select(from: [], prefersDepth: false) == nil)
    }
}
