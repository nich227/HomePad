import Foundation
import Testing
@testable import HomePadAssistantCore

@Suite struct AvailabilityTests {
    private let start = Fixtures.start

    @Test func init_whenEachSystemStatus_thenMapsToOwnCase() {
        #expect(AssistantAvailability(.available) == .available)
        #expect(AssistantAvailability(.unavailable(.appleIntelligenceNotEnabled)) == .needsAppleIntelligence)
        #expect(AssistantAvailability(.unavailable(.deviceNotEligible)) == .deviceNotEligible)
        #expect(AssistantAvailability(.unavailable(.modelNotReady)) == .preparing)
        #expect(AssistantAvailability(.unavailable(.other)) == .unknown)
    }

    @Test func decision_whenAvailable_thenRuns() {
        let state = AssistantGateState(.available, at: start)
        #expect(state.decision(at: start) == .run)
        #expect(state.decision(at: start).mayRun)
        #expect(!state.shouldRecheck)
    }

    @Test func decision_whenNotAvailable_thenBlockedWithTheReason() {
        #expect(AssistantGateState(.needsAppleIntelligence, at: start).decision(at: start) == .blocked(.needsAppleIntelligence))
        #expect(AssistantGateState(.deviceNotEligible, at: start).decision(at: start) == .blocked(.deviceNotEligible))
        #expect(AssistantGateState(.unknown, at: start).decision(at: start) == .blocked(.unknown))
        #expect(!AssistantGateDecision.blocked(.unknown).mayRun)
        #expect(!AssistantGateDecision.gettingReady.mayRun)
    }

    @Test func decision_whenPreparingAtLaunch_thenWaitsAndDoesNotRunTheHub() {
        let state = AssistantGateState(.preparing, at: start)
        #expect(state.decision(at: start) == .gettingReady)
        #expect(state.decision(at: start + AssistantGateState.preparingGracePeriod - 1) == .gettingReady)
        #expect(state.shouldRecheck)
    }

    @Test func decision_whenPreparingPastTheGracePeriod_thenBlocked() {
        let state = AssistantGateState(.preparing, at: start)
        #expect(state.decision(at: start + AssistantGateState.preparingGracePeriod) == .blocked(.stillPreparing))
    }

    @Test func decision_whenRunningHubStartsPreparing_thenKeepsRunningForTheGracePeriodOnly() {
        var state = AssistantGateState(.available, at: start)
        state.update(.preparing, at: start + 100)
        #expect(state.decision(at: start + 101) == .run)
        // Reading the same value again does not restart the grace period.
        state.update(.preparing, at: start + 500)
        #expect(state.since == start + 100)
        #expect(state.decision(at: start + 100 + AssistantGateState.preparingGracePeriod) == .blocked(.stillPreparing))
        state.update(.available, at: start + 2_000)
        #expect(state.decision(at: start + 2_000) == .run)
    }

    @Test func decision_whenTurnedOffAndBackOn_thenPreparingWaitsAgain() {
        var state = AssistantGateState(.available, at: start)
        state.update(.needsAppleIntelligence, at: start + 10)
        #expect(!state.hubHasRun)
        state.update(.preparing, at: start + 20)
        #expect(state.decision(at: start + 21) == .gettingReady)
        state.update(.deviceNotEligible, at: start + 30)
        state.update(.unknown, at: start + 40)
        #expect(state.decision(at: start + 41) == .blocked(.unknown))
    }

    @Test func decision_whenBypassed_thenRunsWhateverTheAvailability() {
        let state = AssistantGateState(.deviceNotEligible, at: start, isBypassed: true)
        #expect(state.decision(at: start) == .run)
        #expect(!AssistantGateState(.preparing, at: start, isBypassed: true).shouldRecheck)
    }

    @Test func testHooks_whenEnvironmentIsEmpty_thenEverythingIsOff() {
        #expect(AssistantTestHooks.none == AssistantTestHooks(environment: ["HOMEPAD_UITEST_SKIP_AI_GATE": "0"]))
        #expect(!AssistantTestHooks.none.skipsAppleIntelligenceGate)
        #expect(!AssistantTestHooks.none.usesScriptedAssistant)
    }

    @Test func testHooks_whenVariablesAreSet_thenSwitchesAreOn() {
        let hooks = AssistantTestHooks(environment: ["HOMEPAD_UITEST_SKIP_AI_GATE": "1", "HOMEPAD_UITEST_SCRIPTED_ASSISTANT": "1"])
        #expect(hooks.skipsAppleIntelligenceGate)
        #expect(hooks.usesScriptedAssistant)
    }
}

@Suite struct FailureTests {
    @Test func init_whenErrorIsAnAssistantFailure_thenPassesThrough() {
        #expect(AssistantFailure(AssistantFailure.refused) == .refused)
        #expect(AssistantFailure(TestError()) == .unknown)
    }

    @Test func init_whenModelErrorKind_thenMapsEveryCase() {
        let expected: [ModelErrorKind: AssistantFailure] = [
            .contextSizeExceeded: .contextTooLong, .guardrailViolation: .refused, .refusal: .refused,
            .rateLimited: .busy, .concurrentRequests: .busy, .assetsUnavailable: .modelUnavailable,
            .unsupportedLanguage: .unsupportedLanguage, .timeout: .timedOut, .other: .unknown,
        ]
        for kind in ModelErrorKind.allCases {
            #expect(AssistantFailure(kind) == expected[kind])
        }
    }

    @Test func init_whenSpeechErrorKind_thenMapsEveryCase() {
        let expected: [SpeechErrorKind: AssistantFailure] = [
            .recognizerUnavailable: .speechUnavailable, .onDeviceUnsupported: .speechUnavailable,
            .speechDenied: .speechNotPermitted, .microphoneDenied: .microphoneNotPermitted,
            .interrupted: .interrupted, .noSpeech: .noSpeech, .other: .unknown,
        ]
        for kind in SpeechErrorKind.allCases {
            #expect(AssistantFailure(kind) == expected[kind])
        }
    }
}
