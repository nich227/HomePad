import Foundation
import HomePadCore
import Testing
@testable import HomePadFaceCore

@Suite struct RecognitionEngineTests {
    private let alice = UUID()
    private let bob = UUID()
    private let matchPolicy = MatchPolicy(
        minimumSimilarity: 0.8,
        minimumMargin: 0.1,
        duplicateSimilarity: 0.7,
        enrollmentConsistencySimilarity: 0.5
    )

    private func engine(liveness: LivenessPolicy = LivenessPolicy()) -> RecognitionEngine {
        RecognitionEngine(configuration: RecognitionEngineConfiguration(
            matchPolicies: MatchPolicyTable(fallback: matchPolicy),
            liveness: liveness
        ))
    }

    private func templates() throws -> [FaceTemplate] {
        [try template(alice, degrees: [0]), try template(bob, degrees: [90])]
    }

    /// Feeds `count` frames 0.1 s apart and returns the outcome after each one.
    private func run(
        _ engine: inout RecognitionEngine,
        degrees: Double?,
        count: Int,
        from start: TimeInterval,
        depth: FaceDepthStatistics? = nil,
        size: Double = 0.3,
        pose: HeadPose = .frontal,
        quality: Float = 0.6
    ) throws -> [RecognitionOutcome] {
        try (0..<count).map { index in
            let frame = try frame(at: start + Double(index) * 0.1, degrees: degrees, size: size, pose: pose, quality: quality, depth: depth)
            return engine.process(frame, templates: try templates()).outcome
        }
    }

    @Test func frame_whenBuiltWithAViewerPosition_thenObservationCarriesIt() throws {
        let position = FaceViewerPosition(x: 0.25, y: 0.75)
        #expect(try frame(at: 0, degrees: 0, position: position).primary?.viewerPosition == position)
        #expect(try frame(at: 0, degrees: 0).primary?.viewerPosition == nil)
    }

    @Test func process_whenNoFace_thenNobodyAndNoChange() {
        var engine = engine()
        let update = engine.process(.empty(at: 0), templates: [])
        #expect(update == .idle)
        #expect(engine.latest == .idle)
    }

    @Test func process_whenEnrolledFaceIsLive_thenUnlocksAfterStableMatches() throws {
        var engine = engine()
        let outcomes = try run(&engine, degrees: 5, count: 3, from: 0, depth: faceLikeDepth())
        #expect(outcomes == [.unknownPerson, .unknownPerson, .unlocked(alice)])
        #expect(engine.latest.didChange)
        #expect(engine.latest.isFacePresent)
        #expect(engine.latest.proximity == .near)
        #expect(engine.latest.liveness == LivenessAssessment(verdict: .live, evidence: .depth, grant: .unlockPersonalContent))
        #expect(try run(&engine, degrees: 5, count: 1, from: 1, depth: faceLikeDepth()) == [.unlocked(alice)])
        #expect(!engine.latest.didChange)
    }

    @Test func process_whenEnrolledFaceHasNoDepth_thenPersonalizesWithoutUnlocking() throws {
        var engine = engine()
        #expect(try run(&engine, degrees: 5, count: 3, from: 0).last == .personalized(alice))
        #expect(engine.latest.liveness?.grant == .personalizeOnly)
        #expect(engine.latest.outcome.profileID == alice)
    }

    @Test func process_whenIndeterminateMayNotPersonalize_thenTreatedAsUnknown() throws {
        var engine = engine(liveness: LivenessPolicy(indeterminateMayPersonalize: false))
        #expect(try run(&engine, degrees: 5, count: 5, from: 0).last == .unknownPerson)
        #expect(engine.latest.liveness?.grant == .deny)
    }

    @Test func process_whenEnrolledFaceIsFlat_thenTreatedAsUnknown() throws {
        var engine = engine()
        let outcomes = try run(&engine, degrees: 5, count: 6, from: 0, depth: flatDepth())
        #expect(outcomes.allSatisfy { $0 == .unknownPerson })
        #expect(engine.latest.liveness?.verdict == .spoofSuspected)
        #expect(engine.latest.outcome.profileID == nil)
    }

    @Test func process_whenFaceIsNotEnrolled_thenUnknownPerson() throws {
        var engine = engine()
        #expect(try run(&engine, degrees: 45, count: 5, from: 0, depth: faceLikeDepth()).last == .unknownPerson)
        #expect(engine.latest.liveness == nil)
    }

    @Test func process_whenTemplatesComeFromAnotherModel_thenUnknownPerson() throws {
        var engine = engine()
        let other = [try template(alice, degrees: [0], model: "other.model")]
        for index in 0..<5 {
            engine.process(try frame(at: Double(index) * 0.1, degrees: 0), templates: other)
        }
        #expect(engine.latest.outcome == .unknownPerson)
    }

    @Test func process_whenFrameCannotBeJudged_thenNeverRecognizes() throws {
        var blurry = engine()
        #expect(try run(&blurry, degrees: 5, count: 5, from: 0, quality: 0.05).last == .unknownPerson)
        var turned = engine()
        #expect(try run(&turned, degrees: 5, count: 5, from: 0, pose: pose(yaw: 60)).last == .unknownPerson)
        var tilted = engine()
        #expect(try run(&tilted, degrees: 5, count: 5, from: 0, pose: pose(pitch: -50)).last == .unknownPerson)
        var noEmbedding = engine()
        #expect(try run(&noEmbedding, degrees: nil, count: 5, from: 0).last == .unknownPerson)
    }

    @Test func process_whenFaceSizeCrossesTheBound_thenProximityChangeIsReported() throws {
        var engine = engine()
        _ = try run(&engine, degrees: 45, count: 2, from: 0, size: 0.1)
        #expect(engine.latest.proximity == .far)
        #expect(!engine.latest.didChange)
        _ = try run(&engine, degrees: 45, count: 1, from: 1, size: 0.3)
        #expect(engine.latest.proximity == .near)
        #expect(engine.latest.didChange)
    }

    @Test func process_whenLiveMemberIsReplacedByAnotherFaceWithoutDepth_thenEvidenceDoesNotCarryOver() throws {
        var engine = engine()
        #expect(try run(&engine, degrees: 0, count: 3, from: 0, depth: faceLikeDepth()).last == .unlocked(alice))
        let outcomes = try run(&engine, degrees: 90, count: 6, from: 1)
        #expect(!outcomes.contains(.unlocked(bob)))
        #expect(!outcomes.contains(.unlocked(alice)))
        #expect(outcomes.last == .personalized(bob))
    }

    @Test func process_whenLiveStrangerIsFollowedByAnEnrolledFaceWithoutDepth_thenNoUnlock() throws {
        var engine = engine()
        #expect(try run(&engine, degrees: 45, count: 5, from: 0, depth: faceLikeDepth()).last == .unknownPerson)
        #expect(try run(&engine, degrees: 0, count: 6, from: 1).last == .personalized(alice))
    }

    @Test func process_whenOneStrayFrameMatchesSomeoneElse_thenUnlockIsDowngradedUntilEvidenceIsFresh() throws {
        var engine = engine()
        _ = try run(&engine, degrees: 0, count: 3, from: 0, depth: faceLikeDepth())
        #expect(try run(&engine, degrees: 90, count: 1, from: 1) == [.personalized(alice)])
        #expect(engine.latest.liveness?.evidence == LivenessEvidence.none)
        #expect(try run(&engine, degrees: 0, count: 2, from: 1.1, depth: faceLikeDepth()) == [.personalized(alice), .unlocked(alice)])
    }

    @Test func process_whenFaceLeavesPastTheLockDelay_thenNobodyAndEvidenceIsDropped() throws {
        var engine = engine()
        _ = try run(&engine, degrees: 0, count: 3, from: 0, depth: faceLikeDepth())
        #expect(engine.process(.empty(at: 1), templates: try templates()).outcome == .unlocked(alice))
        #expect(!engine.latest.isFacePresent)
        let gone = engine.process(.empty(at: 4), templates: try templates())
        #expect(gone.outcome == .nobody)
        #expect(gone.proximity == .far)
        #expect(gone.didChange)
        #expect(try run(&engine, degrees: 0, count: 3, from: 5).last == .personalized(alice))
    }

    @Test func advance_whenNoFramesArrivePastTheLockDelay_thenNobody() throws {
        var engine = engine()
        _ = try run(&engine, degrees: 0, count: 3, from: 0, depth: faceLikeDepth())
        #expect(engine.advance(to: 1).outcome == .unlocked(alice))
        #expect(engine.advance(to: 10).outcome == .nobody)
        #expect(engine.latest.proximity == .far)
    }

    @Test func reset_whenSomeoneIsRecognized_thenNobody() throws {
        var engine = engine()
        _ = try run(&engine, degrees: 0, count: 3, from: 0, depth: faceLikeDepth())
        let update = engine.reset()
        #expect(update.outcome == .nobody)
        #expect(update.didChange)
        #expect(engine.configuration.stabilizer == StabilizerPolicy())
    }
}

@MainActor
@Suite struct HouseholdSessionDriverTests {
    private let session: HouseholdSession
    private let alice: UUID
    private let bob: UUID
    private let driver = HouseholdSessionDriver()
    private let date = Date(timeIntervalSince1970: 500)

    init() throws {
        session = HouseholdSession(store: InMemoryProfileStore())
        alice = try session.addProfile(name: "Alice").id
        bob = try session.addProfile(name: "Bob").id
    }

    private func update(_ outcome: RecognitionOutcome, _ proximity: Proximity = .near) -> RecognitionUpdate {
        RecognitionUpdate(outcome: outcome, proximity: proximity, isFacePresent: true, liveness: nil, didChange: true)
    }

    @Test func apply_whenUnlocked_thenSessionIsFaceActivatedAndPersonalContentUnlocks() {
        driver.apply(update(.unlocked(alice)), to: session, at: date)
        #expect(session.activation == .face(alice, at: date))
        #expect(session.isPersonalContentUnlocked)
        #expect(session.proximity == .near)
        #expect(session.isSomeonePresent)
        #expect(driver.personalizedProfileID == nil)
    }

    @Test func apply_whenPersonalized_thenSessionSwitchesWithoutUnlocking() {
        driver.apply(update(.personalized(alice), .far), to: session, at: date)
        #expect(session.activation == .manual(alice))
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .far)
        #expect(driver.personalizedProfileID == alice)
    }

    @Test func apply_whenUnlockIsDowngradedToPersonalized_thenPersonalContentLocks() {
        driver.apply(update(.unlocked(alice)), to: session, at: date)
        driver.apply(update(.personalized(alice)), to: session, at: date)
        #expect(session.activation == .manual(alice))
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func apply_whenPersonalizedMemberLeaves_thenSessionLocks() {
        driver.apply(update(.personalized(alice)), to: session, at: date)
        driver.apply(update(.nobody, .far), to: session, at: date)
        #expect(session.activation == .none)
        #expect(!session.isSomeonePresent)
        #expect(driver.personalizedProfileID == nil)
    }

    @Test func apply_whenPersonalizedMemberIsReplacedByAStranger_thenSessionLocks() {
        driver.apply(update(.personalized(alice)), to: session, at: date)
        driver.apply(update(.unknownPerson), to: session, at: date)
        #expect(session.activation == .none)
        #expect(session.isSomeonePresent)
    }

    @Test func apply_whenUnlockedMemberIsReplacedByAStranger_thenPersonalContentLocks() {
        driver.apply(update(.unlocked(alice)), to: session, at: date)
        driver.apply(update(.unknownPerson), to: session, at: date)
        #expect(session.activation == .none)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func apply_whenProfileWasPickedByHand_thenLeavingDoesNotUndoIt() throws {
        try session.switchManually(to: bob)
        driver.apply(update(.unknownPerson), to: session, at: date)
        driver.apply(update(.nobody), to: session, at: date)
        #expect(session.activation == .manual(bob))
    }

    @Test func apply_whenSomeoneSwitchedByHandAfterFacePersonalization_thenLeavingKeepsTheirChoice() throws {
        driver.apply(update(.personalized(alice)), to: session, at: date)
        try session.switchManually(to: bob)
        driver.apply(update(.nobody), to: session, at: date)
        #expect(session.activation == .manual(bob))
        #expect(driver.personalizedProfileID == nil)
    }

    @Test func apply_whenPersonalizedMemberWasRemoved_thenSessionLocks() {
        driver.apply(update(.personalized(alice)), to: session, at: date)
        driver.apply(update(.personalized(UUID())), to: session, at: date)
        #expect(session.activation == .none)
        #expect(driver.personalizedProfileID == nil)
    }

    @Test func apply_whenPersonalizedThenUnlocked_thenFaceActivationReplacesManual() {
        driver.apply(update(.personalized(alice)), to: session, at: date)
        driver.apply(update(.unlocked(alice)), to: session, at: date)
        #expect(session.activation == .face(alice, at: date))
        #expect(driver.personalizedProfileID == nil)
    }
}

@Suite struct FaceSettingsTests {
    @Test func descriptors_whenListed_thenEveryKeyIsPrefixedAndInTheFacePane() {
        #expect(FaceSettings.descriptors.count == 5)
        #expect(FaceSettings.descriptors.allSatisfy { $0.name.hasPrefix("face.") && $0.pane == "Face Recognition" })
        #expect(Set(FaceSettings.descriptors.map(\.name)).count == 5)
    }

    @Test func descriptors_whenChoice_thenDefaultIsOneOfTheOptions() throws {
        let delay = try #require(FaceSettings.descriptors.first { $0.name == FaceSettings.lockDelaySeconds.name })
        #expect(delay.control == .choice([
            .init(title: "1 second", value: "1"),
            .init(title: "3 seconds", value: "3"),
            .init(title: "5 seconds", value: "5"),
            .init(title: "10 seconds", value: "10"),
            .init(title: "30 seconds", value: "30"),
        ]))
        #expect(delay.defaultValue == .integer(3))
        let near = try #require(FaceSettings.descriptors.first { $0.name == FaceSettings.nearDistance.name })
        guard case .choice(let options) = near.control else {
            Issue.record("near distance is not a choice")
            return
        }
        #expect(options.map(\.value) == FaceSettings.NearDistance.allCases.map(\.rawValue))
        #expect(near.defaultValue == .string("standard"))
        let strictness = try #require(FaceSettings.descriptors.first { $0.name == FaceSettings.matchStrictness.name })
        guard case .choice(let levels) = strictness.control else {
            Issue.record("match strictness is not a choice")
            return
        }
        #expect(levels.map(\.value) == MatchStrictness.allCases.map(\.rawValue))
        #expect(strictness.defaultValue == .string("standard"))
    }

    @Test func values_whenDefaulted_thenMatchKeyDefaults() {
        let values = FaceSettingsValues()
        #expect(values.recognitionEnabled)
        #expect(values.indeterminateLivenessPersonalizes)
        #expect(values.lockDelay == 3)
        #expect(values.nearDistance == .standard)
        #expect(values.matchStrictness == .standard)
    }

    @Test func values_whenStoredValueIsNotAnOption_thenFallsBackToDefault() {
        let values = FaceSettingsValues(lockDelaySeconds: 7, nearDistance: "sideways", matchStrictness: "loose")
        #expect(values.lockDelay == 3)
        #expect(values.nearDistance == .standard)
        #expect(values.matchStrictness == .standard)
    }

    @Test func applied_whenStrictnessSet_thenRecognitionBoundsMoveAndEnrollmentGuardsStay() {
        var base = RecognitionEngineConfiguration()
        base.matchPolicies.register(.sFace, forModelID: "sface.FaceEmbedder.128")
        let standard = FaceSettingsValues().applied(to: base).matchPolicies
        #expect(standard == base.matchPolicies)
        let strict = FaceSettingsValues(matchStrictness: "strict").applied(to: base).matchPolicies
        let sFace = strict.policy(forModelID: "sface.FaceEmbedder.128")
        #expect(abs(sFace.minimumSimilarity - 0.443) < 1e-6)
        #expect(abs(sFace.minimumMargin - 0.08) < 1e-6)
        #expect(sFace.duplicateSimilarity == MatchPolicy.sFace.duplicateSimilarity)
        #expect(sFace.enrollmentConsistencySimilarity == MatchPolicy.sFace.enrollmentConsistencySimilarity)
        #expect(strict.fallback.minimumSimilarity > MatchPolicy.conservativeDefault.minimumSimilarity)
        let relaxed = FaceSettingsValues(matchStrictness: "relaxed").applied(to: base).matchPolicies
        #expect(abs(relaxed.policy(forModelID: "sface.FaceEmbedder.128").minimumSimilarity - 0.323) < 1e-6)
        #expect(relaxed.policy(forModelID: "sface.FaceEmbedder.128").minimumMargin == MatchPolicy.sFace.minimumMargin)
    }

    @Test func adjusted_whenPolicyIsAlreadyNearOne_thenSimilarityStaysBelowOne() {
        #expect(MatchPolicy.featurePrintDevelopment.adjusted(for: .strict).minimumSimilarity <= 0.99)
        let nearOne = MatchPolicy(minimumSimilarity: 0.97, minimumMargin: 0, duplicateSimilarity: 0.9, enrollmentConsistencySimilarity: 0.9)
        #expect(nearOne.adjusted(for: .strict).minimumSimilarity == 0.99)
    }

    @Test func applied_whenPreferencesSet_thenEngineConfigurationFollows() {
        let values = FaceSettingsValues(
            recognitionEnabled: false,
            indeterminateLivenessPersonalizes: false,
            lockDelaySeconds: 10,
            nearDistance: "farther"
        )
        let configuration = values.applied(to: RecognitionEngineConfiguration())
        #expect(!values.recognitionEnabled)
        #expect(configuration.stabilizer.absenceTimeout == 10)
        #expect(configuration.stabilizer.matchTimeout == 10)
        #expect(!configuration.liveness.indeterminateMayPersonalize)
        #expect(configuration.proximity == .farther)
        #expect(FaceSettingsValues(nearDistance: "closer").applied(to: RecognitionEngineConfiguration()).proximity == .closer)
    }
}
