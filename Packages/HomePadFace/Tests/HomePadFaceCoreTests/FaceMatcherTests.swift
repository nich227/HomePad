import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct FaceMatcherTests {
    private let alice = UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID()
    private let bob = UUID(uuidString: "00000000-0000-0000-0000-00000000000B") ?? UUID()
    private let carol = UUID(uuidString: "00000000-0000-0000-0000-00000000000C") ?? UUID()
    private let policy = MatchPolicy(
        minimumSimilarity: 0.8,
        minimumMargin: 0.1,
        duplicateSimilarity: 0.7,
        enrollmentConsistencySimilarity: 0.5
    )
    private var matcher: FaceMatcher {
        FaceMatcher(policies: MatchPolicyTable(policies: [testModelID: policy]))
    }

    @Test func match_whenBestIsAboveThresholdWithMargin_thenMatches() throws {
        let templates = [try template(alice, degrees: [0]), try template(bob, degrees: [90]), try template(carol, degrees: [180])]
        let result = matcher.match(try vector(10), against: templates)
        #expect(result.decision == .match(alice))
        #expect(result.matchedProfileID == alice)
        #expect(result.best?.profileID == alice)
        #expect(result.secondBest?.profileID == bob)
        #expect(abs((result.best?.similarity ?? 0) - Float(cos(radians(10)))) < 1e-5)
    }

    @Test func match_whenBestIsBelowThreshold_thenBelowThreshold() throws {
        let result = matcher.match(try vector(45), against: [try template(alice, degrees: [0])])
        #expect(result.decision == .belowThreshold)
        #expect(result.matchedProfileID == nil)
        #expect(result.best?.profileID == alice)
    }

    @Test func match_whenRunnerUpIsTooClose_thenAmbiguous() throws {
        let templates = [try template(alice, degrees: [0]), try template(bob, degrees: [20])]
        let result = matcher.match(try vector(8), against: templates)
        #expect(result.decision == .ambiguous)
        #expect(result.best?.profileID == alice)
        #expect(result.secondBest?.profileID == bob)
    }

    @Test func match_whenOnlyOneProfileEnrolled_thenNoMarginNeeded() throws {
        let result = matcher.match(try vector(5), against: [try template(alice, degrees: [0])])
        #expect(result.decision == .match(alice))
        #expect(result.secondBest == nil)
    }

    @Test func match_whenTemplatesComeFromAnotherModel_thenNoComparableTemplates() throws {
        let result = matcher.match(try vector(0), against: [try template(alice, degrees: [0], model: "other.model")])
        #expect(result.decision == .noComparableTemplates)
        #expect(result.best == nil)
    }

    @Test func match_whenNoTemplates_thenNoComparableTemplates() throws {
        #expect(matcher.match(try vector(0), against: []).decision == .noComparableTemplates)
    }

    @Test func match_whenProfileHasSeveralTemplates_thenUsesItsBestSample() throws {
        let templates = [try template(alice, degrees: [80]), try template(alice, degrees: [2]), try template(bob, degrees: [90])]
        let result = matcher.match(try vector(0), against: templates)
        #expect(result.decision == .match(alice))
        #expect(abs((result.best?.similarity ?? 0) - Float(cos(radians(2)))) < 1e-5)
    }

    @Test func match_whenTwoProfilesTie_thenOrderIsStableAndAmbiguous() throws {
        let templates = [try template(bob, degrees: [0]), try template(alice, degrees: [0])]
        let result = matcher.match(try vector(0), against: templates)
        #expect(result.decision == .ambiguous)
        #expect(result.best?.profileID == alice)
        #expect(matcher.match(try vector(0), against: templates.reversed()).best?.profileID == alice)
    }

    @Test func policy_whenModelUnknown_thenFallsBackToConservativeDefault() {
        var table = MatchPolicyTable()
        #expect(table.policy(forModelID: "unknown") == .conservativeDefault)
        table.register(.featurePrintDevelopment, forModelID: "vision")
        #expect(table.policy(forModelID: "vision") == .featurePrintDevelopment)
        #expect(table.fallback == .conservativeDefault)
    }

    @Test func match_whenModelHasNoRegisteredPolicy_thenUsesFallbackThreshold() throws {
        let strict = FaceMatcher()
        let lenient = FaceMatcher(policies: MatchPolicyTable(fallback: MatchPolicy(
            minimumSimilarity: 0.5, minimumMargin: 0, duplicateSimilarity: 0.5, enrollmentConsistencySimilarity: 0.5
        )))
        let templates = [try template(alice, degrees: [0])]
        #expect(strict.match(try vector(60), against: templates).decision == .belowThreshold)
        #expect(lenient.match(try vector(45), against: templates).decision == .match(alice))
    }
}
