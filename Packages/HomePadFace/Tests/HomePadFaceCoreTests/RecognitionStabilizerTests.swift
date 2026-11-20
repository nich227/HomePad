import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct RecognitionStabilizerTests {
    private let alice = UUID()
    private let bob = UUID()

    /// Feeds frames 0.1 s apart starting at `start` and returns the emitted decisions.
    @discardableResult
    private func feed(
        _ stabilizer: inout RecognitionStabilizer,
        _ identities: [FrameIdentity],
        from start: TimeInterval = 0
    ) -> [PresenceDecision] {
        identities.enumerated().compactMap { index, identity in
            stabilizer.ingest(identity, at: start + Double(index) * 0.1)
        }
    }

    @Test func ingest_whenNoFaceFromTheStart_thenStaysNobody() {
        var stabilizer = RecognitionStabilizer()
        #expect(feed(&stabilizer, [.noFace, .noFace]).isEmpty)
        #expect(stabilizer.decision == .nobody)
    }

    @Test func ingest_whenThreeOfFiveFramesMatch_thenRecognized() {
        var stabilizer = RecognitionStabilizer()
        let events = feed(&stabilizer, [.matched(alice), .unmatched, .matched(alice), .matched(alice)])
        #expect(events == [.unknownPerson, .recognized(alice)])
    }

    @Test func ingest_whenOnlyTwoFramesMatch_thenNotRecognized() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .unmatched, .unmatched, .unmatched, .unmatched])
        #expect(stabilizer.decision == .unknownPerson)
    }

    @Test func ingest_whenUnusableFaceAppears_thenUnknownPerson() {
        var stabilizer = RecognitionStabilizer()
        #expect(stabilizer.ingest(.unusable, at: 0) == .unknownPerson)
        #expect(stabilizer.ingest(.unusable, at: 0.1) == nil)
    }

    @Test func ingest_whenRecognizedAndThreeConsecutiveMisses_thenDropsToUnknown() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(feed(&stabilizer, [.unmatched, .unmatched], from: 1).isEmpty)
        #expect(stabilizer.decision == .recognized(alice))
        #expect(stabilizer.ingest(.unmatched, at: 1.2) == .unknownPerson)
    }

    @Test func ingest_whenMissesAreInterruptedByAMatch_thenStaysRecognized() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        let events = feed(&stabilizer, [.unmatched, .unmatched, .matched(alice), .unmatched, .unmatched], from: 1)
        #expect(events.isEmpty)
        #expect(stabilizer.decision == .recognized(alice))
    }

    @Test func ingest_whenFaceLeavesBriefly_thenHoldsUntilAbsenceTimeout() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(absenceTimeout: 3))
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.ingest(.noFace, at: 2) == nil)
        #expect(stabilizer.ingest(.noFace, at: 3.1) == nil)
        #expect(stabilizer.ingest(.noFace, at: 3.3) == .nobody)
        #expect(feed(&stabilizer, [.matched(alice), .matched(alice)], from: 4) == [.unknownPerson])
    }

    @Test func advance_whenNoFramesArriveForAbsenceTimeout_thenNobody() {
        var stabilizer = RecognitionStabilizer()
        #expect(stabilizer.advance(to: 100) == nil)
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.advance(to: 1) == nil)
        #expect(stabilizer.advance(to: 3.3) == .nobody)
    }

    @Test func ingest_whenFaceStaysButCannotBeJudgedPastMatchTimeout_thenUnknown() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(matchTimeout: 2))
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.ingest(.unusable, at: 1) == nil)
        #expect(stabilizer.ingest(.unusable, at: 2.5) == .unknownPerson)
    }

    @Test func ingest_whenOneStrayFrameMatchesSomeoneElse_thenStaysRecognized() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(feed(&stabilizer, [.matched(bob), .matched(alice), .matched(alice)], from: 1).isEmpty)
    }

    @Test func ingest_whenTwoProfilesAlternate_thenLocksOnceAndDoesNotFlap() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        let alternating = (0..<20).map { $0.isMultiple(of: 2) ? FrameIdentity.matched(bob) : .matched(alice) }
        #expect(feed(&stabilizer, alternating, from: 1) == [.unknownPerson])
    }

    @Test func ingest_whenSomeoneElseTakesOver_thenLocksFirstThenRecognizesThem() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        let events = feed(&stabilizer, [.matched(bob), .matched(bob), .matched(bob), .matched(bob)], from: 1)
        #expect(events == [.unknownPerson, .recognized(bob)])
    }

    @Test func ingest_whenProfileDroppedThisFrame_thenStaleMatchesDoNotWinItBack() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(requiredMatches: 2, missesToDrop: 1))
        feed(&stabilizer, [.matched(alice), .matched(alice)])
        #expect(stabilizer.decision == .recognized(alice))
        #expect(stabilizer.ingest(.unmatched, at: 1) == .unknownPerson)
    }

    @Test func ingest_whenMatchTimesOutOnAJudgedFrame_thenUnknown() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(missesToDrop: 10, matchTimeout: 2))
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.ingest(.unmatched, at: 2.3) == .unknownPerson)
    }

    @Test func ingest_whenTwoProfilesQualifyAtOnce_thenUnknown() {
        let policy = StabilizerPolicy(requiredMatches: 1, maximumCompetingMatches: 2, missesToDrop: 10, matchTimeout: 3)
        var stabilizer = RecognitionStabilizer(policy: policy)
        #expect(stabilizer.ingest(.matched(alice), at: 0) == .recognized(alice))
        #expect(stabilizer.ingest(.matched(bob), at: 3) == .unknownPerson)
    }

    @Test func ingest_whenOldMatchesAgeOut_thenTheyNoLongerCount() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(matchTimeout: 1, absenceTimeout: 10))
        stabilizer.ingest(.matched(alice), at: 0)
        stabilizer.ingest(.matched(alice), at: 0.1)
        #expect(stabilizer.ingest(.matched(alice), at: 5) == nil)
        #expect(stabilizer.decision == .unknownPerson)
    }

    @Test func hasJudgedStranger_whenFaceCannotBeJudged_thenFalse() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(matchTimeout: 2))
        #expect(!stabilizer.hasJudgedStranger)
        stabilizer.ingest(.unusable, at: 0)
        #expect(stabilizer.decision == .unknownPerson)
        #expect(!stabilizer.hasJudgedStranger)

        stabilizer.reset()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.ingest(.unusable, at: 2.5) == .unknownPerson)
        #expect(!stabilizer.hasJudgedStranger)
        feed(&stabilizer, [.unusable, .unusable, .unusable, .unusable], from: 3)
        #expect(!stabilizer.hasJudgedStranger)
    }

    @Test func hasJudgedStranger_whenJudgedFramesInARowMatchNobody_thenTrueAtTheThird() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.unmatched, .unusable, .unmatched])
        #expect(stabilizer.decision == .unknownPerson)
        #expect(!stabilizer.hasJudgedStranger)
        stabilizer.ingest(.unmatched, at: 1)
        #expect(stabilizer.hasJudgedStranger)
        feed(&stabilizer, [.unusable, .matched(alice)], from: 2)
        #expect(stabilizer.decision == .unknownPerson)
        #expect(stabilizer.hasJudgedStranger)
    }

    @Test func hasJudgedStranger_whenAMatchBreaksTheRun_thenStaysFalse() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.unmatched, .unmatched, .matched(alice), .unmatched, .unmatched])
        #expect(stabilizer.decision == .unknownPerson)
        #expect(!stabilizer.hasJudgedStranger)
    }

    @Test func hasJudgedStranger_whenRecognizedProfileIsDropped_thenTrueUntilSomeoneIsRecognized() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(!stabilizer.hasJudgedStranger)
        feed(&stabilizer, [.matched(bob), .unmatched], from: 1)
        #expect(!stabilizer.hasJudgedStranger)
        #expect(stabilizer.ingest(.matched(bob), at: 1.2) == .unknownPerson)
        #expect(stabilizer.hasJudgedStranger)

        feed(&stabilizer, [.matched(bob), .matched(bob)], from: 1.3)
        #expect(stabilizer.decision == .recognized(bob))
        #expect(!stabilizer.hasJudgedStranger)

        let alternating = (0..<6).map { $0.isMultiple(of: 2) ? FrameIdentity.matched(alice) : .matched(bob) }
        feed(&stabilizer, alternating, from: 2)
        #expect(stabilizer.decision == .unknownPerson)
        #expect(stabilizer.hasJudgedStranger)
        stabilizer.ingest(.noFace, at: 20)
        #expect(stabilizer.decision == .nobody)
        #expect(!stabilizer.hasJudgedStranger)
    }

    @Test func hasJudgedStranger_whenMatchTimesOutOnOneJudgedFrame_thenNotYet() {
        var stabilizer = RecognitionStabilizer(policy: StabilizerPolicy(missesToDrop: 10, matchTimeout: 2))
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        #expect(stabilizer.ingest(.unmatched, at: 2.3) == .unknownPerson)
        #expect(!stabilizer.hasJudgedStranger)
    }

    @Test func reset_whenRecognized_thenNobody() {
        var stabilizer = RecognitionStabilizer()
        feed(&stabilizer, [.matched(alice), .matched(alice), .matched(alice)])
        stabilizer.reset()
        #expect(stabilizer.decision == .nobody)
    }

    @Test func policy_whenValuesOutOfRange_thenClamped() {
        let policy = StabilizerPolicy(
            windowSize: 0, requiredMatches: 9, maximumCompetingMatches: -1, missesToDrop: 0, matchTimeout: -1, absenceTimeout: -1
        )
        #expect(policy.windowSize == 1)
        #expect(policy.requiredMatches == 1)
        #expect(policy.maximumCompetingMatches == 0)
        #expect(policy.missesToDrop == 1)
        #expect(policy.matchTimeout == 0)
        #expect(policy.absenceTimeout == 0)
    }
}
