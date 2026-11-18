import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct FaceDepthStatisticsTests {
    @Test func init_whenSurfaceIsATiltedPlane_thenResidualAndReliefAreNearZero() {
        let statistics = flatDepth()
        #expect(statistics.sampleCount == 144)
        #expect(statistics.validCount == 144)
        #expect(statistics.validFraction == 1)
        #expect(abs(statistics.medianDepth - 0.5) < 0.005)
        #expect(statistics.planeResidual < 0.0005)
        #expect(abs(statistics.centerRelief) < 0.002)
    }

    @Test func init_whenSurfaceHasFaceLikeRelief_thenResidualAndReliefAreLarge() {
        let statistics = faceLikeDepth()
        #expect(statistics.planeResidual > 0.006)
        #expect(statistics.centerRelief > 0.015)
    }

    @Test func init_whenReadingsAreInvalidOrFarFromMedian_thenTheyAreExcluded() {
        var points = depthGrid { _, _ in 0.5 }
        points[0] = DepthPoint(x: 0, y: 0, depth: .nan)
        points[1] = DepthPoint(x: 0, y: 0, depth: 0)
        points[2] = DepthPoint(x: 0, y: 0, depth: -1)
        points[3] = DepthPoint(x: 0, y: 0, depth: 3)
        let statistics = FaceDepthStatistics(points: points)
        #expect(statistics.sampleCount == 144)
        #expect(statistics.validCount == 140)
        #expect(abs(statistics.validFraction - 140.0 / 144.0) < 1e-6)
        #expect(statistics.planeResidual < 0.0005)
    }

    @Test func init_whenNoPoints_thenEverythingIsZero() {
        let statistics = FaceDepthStatistics(points: [])
        #expect(statistics == FaceDepthStatistics(sampleCount: 0, validCount: 0, medianDepth: 0, planeResidual: 0, centerRelief: 0))
        #expect(statistics.validFraction == 0)
    }

    @Test func init_whenTooFewPointsForAPlane_thenResidualIsZero() {
        let points = [0.1, 0.3, 0.5, 0.7, 0.9].map { DepthPoint(x: Float($0), y: Float($0 * $0), depth: 0.5 + Float($0) * 0.05) }
        #expect(FaceDepthStatistics(points: points).planeResidual == 0)
    }

    @Test func init_whenPointsLieOnOneLine_thenResidualIsZero() {
        let points = (0..<10).map { DepthPoint(x: Float($0) / 10, y: Float($0) / 10, depth: 0.5 + ($0.isMultiple(of: 2) ? 0.02 : 0)) }
        #expect(FaceDepthStatistics(points: points).planeResidual == 0)
    }

    @Test func median_whenCountIsOddOrEven_thenMiddleOrMeanOfMiddles() {
        #expect(FaceDepthStatistics.median([3, 1, 2]) == 2)
        #expect(FaceDepthStatistics.median([4, 1, 3, 2]) == 2.5)
        #expect(FaceDepthStatistics.median([]) == 0)
    }
}

@Suite struct LivenessEvaluatorTests {
    private let evaluator = LivenessEvaluator()

    private func statistics(valid: Int = 100, of total: Int = 100, median: Float = 0.5, residual: Float, relief: Float) -> FaceDepthStatistics {
        FaceDepthStatistics(sampleCount: total, validCount: valid, medianDepth: median, planeResidual: residual, centerRelief: relief)
    }

    @Test func evaluate_whenFaceHasRelief_thenLive() {
        #expect(evaluator.evaluate(faceLikeDepth()) == .live)
        #expect(evaluator.policy == DepthLivenessPolicy())
    }

    @Test func evaluate_whenSurfaceIsFlat_thenSpoofSuspected() {
        #expect(evaluator.evaluate(flatDepth()) == .spoofSuspected)
    }

    @Test func evaluate_whenNoDepth_thenIndeterminate() {
        #expect(evaluator.evaluate(nil) == .indeterminate)
    }

    @Test func evaluate_whenTooFewValidReadings_thenIndeterminate() {
        #expect(evaluator.evaluate(statistics(valid: 30, of: 30, residual: 0, relief: 0)) == .indeterminate)
        #expect(evaluator.evaluate(statistics(valid: 50, of: 100, residual: 0, relief: 0)) == .indeterminate)
    }

    @Test func evaluate_whenOutsideDepthRange_thenIndeterminate() {
        #expect(evaluator.evaluate(flatDepth(distance: 2)) == .indeterminate)
        #expect(evaluator.evaluate(faceLikeDepth(distance: 0.1)) == .indeterminate)
    }

    @Test func evaluate_whenReliefIsBetweenFlatAndFaceLike_thenIndeterminate() {
        #expect(evaluator.evaluate(statistics(residual: 0.0045, relief: 0.02)) == .indeterminate)
        #expect(evaluator.evaluate(statistics(residual: 0.01, relief: 0.002)) == .indeterminate)
        #expect(evaluator.evaluate(statistics(residual: 0.01, relief: -0.02)) == .indeterminate)
    }
}

@Suite struct ChallengeLivenessTrackerTests {
    private func observe(_ tracker: inout ChallengeLivenessTracker, openness: [Float?], from start: TimeInterval = 0, step: TimeInterval = 0.1) {
        for (index, value) in openness.enumerated() {
            tracker.observe(yaw: 0, eyeOpenness: value, at: start + Double(index) * step)
        }
    }

    private func observe(_ tracker: inout ChallengeLivenessTracker, yawDegrees: [Double], times: [TimeInterval]? = nil) {
        for (index, yaw) in yawDegrees.enumerated() {
            tracker.observe(yaw: radians(yaw), eyeOpenness: nil, at: times?[index] ?? Double(index) * 0.1)
        }
    }

    @Test func observe_whenEyesCloseAndReopenQuickly_thenPassesUntilValidityEnds() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, openness: [0.3, 0.3, 0.3, 0.1])
        #expect(!tracker.hasPassed(at: 0.3))
        observe(&tracker, openness: [0.2, 0.3], from: 0.4)
        #expect(tracker.hasPassed(at: 0.5))
        #expect(tracker.hasPassed(at: 20))
        #expect(!tracker.hasPassed(at: 21))
    }

    @Test func observe_whenEyesStayClosedTooLong_thenNoBlinkAndBaselineRestarts() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, openness: [0.3, 0.3, 0.3, 0.1])
        observe(&tracker, openness: [0.1, 0.1, 0.1], from: 2)
        #expect(!tracker.hasPassed(at: 2.2))
        observe(&tracker, openness: [0.04, 0.1], from: 2.3)
        #expect(tracker.hasPassed(at: 2.4))
    }

    @Test func observe_whenBaselineNotEstablished_thenLowValuesAreNotABlink() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, openness: [0.3, 0.05, 0.3])
        #expect(!tracker.hasPassed(at: 0.2))
    }

    @Test func observe_whenOpennessMissingOrNotFinite_thenIgnored() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, openness: [0.3, 0.3, 0.3, nil, .nan, 0.3])
        tracker.observe(yaw: .nan, eyeOpenness: nil, at: 1)
        #expect(!tracker.hasPassed(at: 1))
    }

    @Test func observe_whenHeadTurnsSmoothly_thenPasses() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, yawDegrees: [0, 4, 8])
        #expect(!tracker.hasPassed(at: 0.2))
        observe(&tracker, yawDegrees: [0, 4, 8, 13])
        #expect(tracker.hasPassed(at: 0.3))
    }

    @Test func observe_whenYawJumpsBetweenFrames_thenSweepStartsOver() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, yawDegrees: [0, 20, 21, 22, 23])
        #expect(!tracker.hasPassed(at: 0.4))
    }

    @Test func observe_whenTurnIsSlowerThanTheWindow_thenDoesNotPass() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, yawDegrees: [0, 5, 10, 13], times: [0, 1, 5, 5.5])
        #expect(!tracker.hasPassed(at: 5.5))
    }

    @Test func reset_whenPassed_thenForgets() {
        var tracker = ChallengeLivenessTracker()
        observe(&tracker, yawDegrees: [0, 4, 8, 13])
        tracker.reset()
        #expect(!tracker.hasPassed(at: 0.3))
    }
}

@Suite struct LivenessTrackerTests {
    private func ingest(_ tracker: inout LivenessTracker, _ depth: FaceDepthStatistics?, at timestamp: TimeInterval) -> LivenessAssessment {
        tracker.ingest(depth: depth, yaw: 0, eyeOpenness: nil, at: timestamp)
    }

    private let live = LivenessAssessment(verdict: .live, evidence: .depth, grant: .unlockPersonalContent)
    private let unverified = LivenessAssessment(verdict: .indeterminate, evidence: .none, grant: .personalizeOnly)
    private let spoof = LivenessAssessment(verdict: .spoofSuspected, evidence: .depth, grant: .deny)

    @Test func ingest_whenTwoLiveDepthFrames_thenLiveAndMayUnlock() {
        var tracker = LivenessTracker()
        #expect(ingest(&tracker, faceLikeDepth(), at: 0) == unverified)
        #expect(ingest(&tracker, faceLikeDepth(), at: 0.1) == live)
    }

    @Test func ingest_whenTwoFlatDepthFrames_thenSpoofAndDenied() {
        var tracker = LivenessTracker()
        #expect(ingest(&tracker, flatDepth(), at: 0) == unverified)
        #expect(ingest(&tracker, flatDepth(), at: 0.1) == spoof)
    }

    @Test func ingest_whenLiveStreakIsBrokenByAFlatFrame_thenNotConfirmed() {
        var tracker = LivenessTracker()
        _ = ingest(&tracker, faceLikeDepth(), at: 0)
        _ = ingest(&tracker, flatDepth(), at: 0.1)
        #expect(ingest(&tracker, faceLikeDepth(), at: 0.2) == unverified)
    }

    @Test func ingest_whenLiveThenFlat_thenRevoked() {
        var tracker = LivenessTracker()
        _ = ingest(&tracker, faceLikeDepth(), at: 0)
        _ = ingest(&tracker, faceLikeDepth(), at: 0.1)
        #expect(ingest(&tracker, flatDepth(), at: 0.2) == live)
        #expect(ingest(&tracker, flatDepth(), at: 0.3) == spoof)
    }

    @Test func ingest_whenSpoofLatchedThenLiveAgain_thenRecovers() {
        var tracker = LivenessTracker()
        _ = ingest(&tracker, flatDepth(), at: 0)
        _ = ingest(&tracker, flatDepth(), at: 0.1)
        #expect(ingest(&tracker, faceLikeDepth(), at: 0.2) == spoof)
        #expect(ingest(&tracker, faceLikeDepth(), at: 0.3) == live)
    }

    @Test func ingest_whenDepthGoesMissing_thenLiveHoldsUntilEvidenceIsTooOld() {
        var tracker = LivenessTracker()
        _ = ingest(&tracker, faceLikeDepth(), at: 0)
        _ = ingest(&tracker, faceLikeDepth(), at: 0.1)
        #expect(ingest(&tracker, nil, at: 20) == live)
        #expect(ingest(&tracker, nil, at: 31) == unverified)
    }

    @Test func ingest_whenEvidenceNeverExpires_thenLiveHolds() {
        var tracker = LivenessTracker(policy: LivenessPolicy(liveEvidenceMaximumAge: nil))
        _ = ingest(&tracker, faceLikeDepth(), at: 0)
        _ = ingest(&tracker, faceLikeDepth(), at: 0.1)
        #expect(tracker.assessment(at: 10_000) == live)
    }

    private func turnHead(_ tracker: inout LivenessTracker) -> LivenessAssessment {
        var last = tracker.assessment(at: 0)
        for (index, yaw) in [0.0, 4, 8, 13].enumerated() {
            last = tracker.ingest(depth: nil, yaw: radians(yaw), eyeOpenness: nil, at: Double(index) * 0.1)
        }
        return last
    }

    @Test func ingest_whenChallengePassedWithoutDepth_thenPersonalizeOnlyByDefault() {
        var tracker = LivenessTracker()
        #expect(turnHead(&tracker) == LivenessAssessment(verdict: .indeterminate, evidence: .challenge, grant: .personalizeOnly))
    }

    @Test func ingest_whenChallengePassedAndPolicyAllows_thenMayUnlock() {
        var tracker = LivenessTracker(policy: LivenessPolicy(passedChallengeMayUnlock: true))
        #expect(turnHead(&tracker) == LivenessAssessment(verdict: .live, evidence: .challenge, grant: .unlockPersonalContent))
    }

    @Test func assessment_whenIndeterminateMayNotPersonalize_thenDenied() {
        let tracker = LivenessTracker(policy: LivenessPolicy(indeterminateMayPersonalize: false))
        #expect(tracker.assessment(at: 0) == LivenessAssessment(verdict: .indeterminate, evidence: .none, grant: .deny))
        #expect(tracker.policy.indeterminateMayPersonalize == false)
    }

    @Test func reset_whenLive_thenEvidenceIsGone() {
        var tracker = LivenessTracker()
        _ = ingest(&tracker, faceLikeDepth(), at: 0)
        _ = ingest(&tracker, faceLikeDepth(), at: 0.1)
        tracker.reset()
        #expect(tracker.assessment(at: 0.2) == unverified)
    }
}
