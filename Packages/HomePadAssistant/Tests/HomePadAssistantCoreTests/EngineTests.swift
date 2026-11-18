import Foundation
import Testing
@testable import HomePadAssistantCore

@MainActor
private final class Rig {
    let actions = FakeActions()
    let hub = FakeHub()
    let responder = FakeResponder()
    let input = FakeSpeechInput()
    let output = FakeSpeechOutput()
    let clock = TestClock()
    var audience = Fixtures.guest
    var preferences = AssistantPreferences(listensOnOpen: false, autoDismissSeconds: 0)
    private(set) lazy var engine = makeEngine(tickEvery: nil)

    /// `tickEvery` nil parks the ticker, so only the test advances timeouts.
    func makeEngine(tickEvery: Duration?) -> AssistantEngine {
        AssistantEngine(
            actions: actions,
            hub: hub,
            audience: { self.audience },
            preferences: { self.preferences },
            responder: responder,
            speechInput: input,
            speechOutput: output,
            reportText: { "Report: " + $0.modelText },
            calendar: Fixtures.utc,
            now: { self.clock.date },
            sleep: { _ in try? await Task.sleep(for: tickEvery ?? .seconds(600)) }
        )
    }

    var phase: AssistantConversation.Phase { engine.conversation.phase }

    func ask(_ text: String = "What is next?") async {
        engine.submit(text)
        await waitUntil { self.phase != .thinking && self.phase != .answering }
    }
}

@MainActor
@Suite struct EngineTests {
    private let rig = Rig()

    @Test func open_whenTheAssistantIsTurnedOff_thenNothingStarts() {
        rig.preferences.isEnabled = false
        #expect(!rig.engine.isEnabled)
        rig.engine.open()
        #expect(!rig.engine.conversation.isOpen)
    }

    @Test func open_whenListenOnOpen_thenHearsTheRequestAnswersAndSpeaks() async {
        rig.preferences.listensOnOpen = true
        rig.responder.script = [.events([.partial("It is"), .final(AssistantModelReply(answer: "It is sunny.", usedContextTags: ["c2"], suggestedFollowUps: ["And tomorrow?"]))])]
        rig.engine.open()
        #expect(rig.engine.isEnabled)
        #expect(rig.phase == .listening)
        #expect(rig.input.starts == 1)

        rig.input.hear("how is the")
        await waitUntil { self.rig.engine.conversation.heard == "how is the" }
        rig.input.hear("how is the weather", isFinal: true)
        await waitUntil { self.rig.phase == .followUps }

        #expect(rig.input.stops == 1)
        #expect(rig.engine.conversation.exchange == AssistantExchange(
            request: "how is the weather",
            answer: "It is sunny.",
            snippets: [Fixtures.weatherItem],
            followUps: [.suggested("And tomorrow?")]
        ))
        await waitUntil { self.rig.output.spoken == ["It is sunny."] }
        await waitUntil { !self.rig.engine.conversation.isSpeaking }
        #expect(rig.hub.contextRequests == 1)
    }

    @Test func submit_whenGuestOrLockedMember_thenThePromptHoldsNoPersonalContext() async {
        rig.engine.open()
        for audience in [Fixtures.guest, Fixtures.manualErica, Fixtures.recognizedLockedErica] {
            rig.audience = audience
            await rig.ask()
        }
        #expect(rig.responder.turns.count == 3)
        for turn in rig.responder.turns {
            for marker in Fixtures.personalMarkers {
                #expect(!turn.prompt.contains(marker))
                #expect(!turn.instructions.contains(marker))
            }
            #expect(turn.prompt.contains("Pasta"))
        }
        #expect(rig.responder.turns[0].capabilities == AssistantPolicy.capabilities(for: .guest))
    }

    @Test func submit_whenUnlockedMember_thenOnlyTheirOwnContextIsInThePrompt() async {
        rig.audience = Fixtures.unlockedErica
        rig.engine.open()
        await rig.ask()
        let prompt = rig.responder.turns[0].prompt
        #expect(prompt.contains("Dentist"))
        #expect(prompt.contains("Time: "))
        #expect(!prompt.contains("Buy milk"))
        #expect(!prompt.contains("Secret party"))

        rig.preferences.usesPersonalContext = false
        await rig.ask()
        #expect(!rig.responder.turns[1].prompt.contains("Dentist"))
    }

    @Test func tick_whenTheSessionHoldsPersonalContextAndTheAudienceChanges_thenClosesAndForgets() async {
        rig.audience = Fixtures.unlockedErica
        rig.engine.open()
        await rig.ask()
        rig.engine.tick()
        #expect(rig.engine.conversation.isOpen)

        rig.audience = Fixtures.guest
        rig.engine.tick()
        #expect(!rig.engine.conversation.isOpen)
        #expect(rig.engine.conversation.exchange == nil)
        #expect(rig.responder.resets == 1)
    }

    @Test func tick_whenNoPersonalContextWasUsedAndTheAudienceChanges_thenStaysOpen() async {
        rig.engine.open()
        await rig.ask()
        rig.audience = Fixtures.manualErica
        rig.engine.tick()
        #expect(rig.engine.conversation.isOpen)
    }

    @Test func submit_whenTheAudienceChangedSinceTheLastRequest_thenStartsAFreshSession() async {
        rig.audience = Fixtures.unlockedErica
        rig.engine.open()
        await rig.ask()
        await rig.ask()
        #expect(rig.responder.resets == 0)

        rig.audience = Fixtures.unlockedDanny
        await rig.ask()
        #expect(rig.responder.resets == 1)
        #expect(rig.responder.turns[2].prompt.contains("Buy milk"))
        #expect(!rig.responder.turns[2].prompt.contains("Dentist"))
        #expect(rig.responder.turns[2].instructions.contains("Danny"))
    }

    @Test func submit_whenTheModelCallsToolsAsAGuest_thenScenesAreRefusedAndSharedThingsWork() async {
        rig.responder.script = [.act([.runScene(name: "Good Night"), .setNightMode(isOn: true)], then: [])]
        rig.engine.open()
        await rig.ask("good night")
        #expect(rig.responder.toolReports.map(\.result) == [.failure(.needsRecognizedMember), .success(.nightMode(true))])
        #expect(rig.actions.calls == ["nightMode true"])
        #expect(rig.engine.conversation.exchange?.answer == "Report: Not done. This needs a household member the hub's camera has recognized. Report: Night Mode is on.")
        #expect(rig.engine.conversation.exchange?.followUps == [.nightMode(isOn: false)])
    }

    @Test func submit_whenTheModelAsksForTooManyActions_thenTheRestAreRefused() async {
        let requests = Array(repeating: AssistantRequest.weather, count: AssistantLimits.maxActionsPerTurn + 2)
        rig.responder.script = [.act(requests, then: [.final(AssistantModelReply(answer: "Sunny."))]), .act([.weather], then: [])]
        rig.engine.open()
        await rig.ask()
        #expect(rig.actions.calls.count == AssistantLimits.maxActionsPerTurn)
        #expect(rig.responder.toolReports.last?.result == .failure(.limitReached))
        // The count starts again with the next request.
        await rig.ask()
        #expect(rig.actions.calls.count == AssistantLimits.maxActionsPerTurn + 1)
    }

    @Test func submit_whenTheModelFails_thenShowsTheFailure() async {
        rig.responder.script = [.fail(AssistantFailure.refused), .fail(TestError()), .events([])]
        rig.engine.open()
        await rig.ask()
        #expect(rig.phase == .failed(.refused))
        await rig.ask()
        #expect(rig.phase == .failed(.unknown))
        await rig.ask()
        #expect(rig.phase == .failed(.unknown))
    }

    @Test func submit_whenTheContextIsTooLong_thenRetriesOnceInAFreshSession() async {
        rig.responder.script = [.fail(AssistantFailure.contextTooLong), .events([.final(AssistantModelReply(answer: "Here you go."))])]
        rig.audience = Fixtures.unlockedErica
        rig.engine.open()
        await rig.ask()
        #expect(rig.phase == .followUps)
        #expect(rig.responder.resets == 1)
        #expect(rig.responder.turns.count == 2)
        // The fresh session was given the personal context again, so the rule still applies.
        rig.audience = .guest
        rig.engine.tick()
        #expect(!rig.engine.conversation.isOpen)
    }

    @Test func submit_whenTheContextIsTooLongTwice_thenFailsWithAnEmptySession() async {
        rig.responder.script = [.fail(AssistantFailure.contextTooLong), .fail(AssistantFailure.contextTooLong)]
        rig.audience = Fixtures.unlockedErica
        rig.engine.open()
        await rig.ask()
        #expect(rig.phase == .failed(.contextTooLong))
        #expect(rig.responder.resets == 2)
        rig.audience = .guest
        rig.engine.tick()
        #expect(rig.engine.conversation.isOpen)
    }

    @Test func submit_whenTheContextIsTooLongAfterAnAction_thenDoesNotRunTheActionTwice() async {
        rig.responder.script = [.actThenFail([.setNightMode(isOn: true)], AssistantFailure.contextTooLong)]
        rig.engine.open()
        await rig.ask()
        #expect(rig.phase == .failed(.contextTooLong))
        #expect(rig.responder.turns.count == 1)
        #expect(rig.actions.calls == ["nightMode true"])
    }

    @Test func cancel_whenTextIsStreaming_thenStopsAndLaterTextIsDropped() async {
        rig.responder.script = [.hang([.partial("**Hel")])]
        rig.engine.open()
        rig.engine.submit("hello")
        await waitUntil { self.rig.phase == .answering }
        #expect(rig.engine.conversation.exchange?.answer == "Hel")
        rig.engine.cancel()
        #expect(rig.phase == .idle)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.phase == .idle)
    }

    @Test func cancel_whenTheHubIsStillGatheringContext_thenTheModelIsNeverAsked() async {
        let (gate, release) = AsyncStream<Void>.makeStream()
        rig.hub.gate = gate
        rig.engine.open()
        rig.engine.submit("hello")
        await waitUntil { self.rig.hub.contextRequests == 1 }
        rig.engine.cancel()
        release.yield()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.responder.turns.isEmpty)
        #expect(rig.phase == .idle)
    }

    @Test func cancel_whenTheModelThrowsOnCancellation_thenTheErrorIsNotShown() async {
        rig.responder.script = [.throwOnCancel]
        rig.engine.open()
        rig.engine.submit("hello")
        await waitUntil { self.rig.responder.turns.count == 1 }
        rig.engine.cancel()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.phase == .idle)
    }

    @Test func toggleListening_whenSpeaking_thenStopsSpeakingAtOnce() async {
        rig.output.holds = true
        rig.engine.open()
        await rig.ask()
        await waitUntil { self.rig.output.spoken.count == 1 }
        #expect(rig.engine.conversation.isSpeaking)
        rig.engine.toggleListening()
        #expect(rig.output.stops == 1)
        #expect(rig.phase == .listening)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.phase == .listening)
        #expect(!rig.engine.conversation.isSpeaking)
    }

    @Test func toggleListening_whenTheMicrophoneFails_thenShowsWhy() async {
        rig.engine.open()
        rig.engine.toggleListening()
        rig.input.end(throwing: AssistantFailure.microphoneNotPermitted)
        await waitUntil { self.rig.phase == .failed(.microphoneNotPermitted) }
    }

    @Test func toggleListening_whenTheRecognizerEndsWithoutAFinalResult_thenSendsWhatWasHeard() async {
        rig.engine.open()
        rig.engine.toggleListening()
        rig.input.hear("lights on")
        await waitUntil { self.rig.engine.conversation.heard == "lights on" }
        rig.input.end()
        await waitUntil { self.rig.phase == .followUps }
        #expect(rig.engine.conversation.exchange?.request == "lights on")
    }

    @Test func toggleListening_whenListeningIsStoppedAndTheRecognizerThrows_thenTheErrorIsNotShown() async {
        rig.input.throwsOnCancel = true
        rig.engine.open()
        rig.engine.toggleListening()
        rig.engine.toggleListening()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.phase == .idle)
        #expect(rig.input.stops == 1)
    }

    @Test func dismiss_whenListening_thenReleasesTheMicrophoneAndForgetsTheConversation() async {
        rig.preferences.listensOnOpen = true
        rig.engine.open()
        rig.engine.noteInteraction()
        rig.engine.dismiss()
        #expect(!rig.engine.conversation.isOpen)
        #expect(rig.input.stops == 1)
        #expect(rig.responder.resets == 1)
        rig.input.hear("anyone there")
        try? await Task.sleep(for: .milliseconds(20))
        #expect(rig.engine.conversation.heard.isEmpty)
    }

    @Test func perform_whenCalledWithoutTheModel_thenTheSameRulesApply() async {
        #expect(await rig.engine.perform(.runScene(name: "Good Night")).result == .failure(.needsRecognizedMember))
        rig.audience = Fixtures.recognizedLockedErica
        #expect(await rig.engine.perform(.runScene(name: "Good Night")).value == .sceneRan("Good Night"))
        #expect(await rig.engine.perform(.setThermostat(degrees: 68, scale: .hub)).value == .thermostat(AssistantThermostat(name: "Hallway", targetCelsius: 20)))
    }

    @Test func ticker_whenNobodyTouchesTheOverlay_thenItClosesByItself() async {
        rig.preferences = AssistantPreferences(listensOnOpen: false, autoDismissSeconds: 15)
        let engine = rig.makeEngine(tickEvery: .milliseconds(2))
        engine.open()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(engine.conversation.isOpen)
        rig.clock.advance(20)
        await waitUntil { !engine.conversation.isOpen }
    }

    @Test func init_whenOnlyTheRequiredPartsAreGiven_thenRunsOnTheRealClock() async {
        let rig = self.rig
        rig.responder.script = [.act([.setNightMode(isOn: true)], then: [])]
        let engine = AssistantEngine(
            actions: rig.actions,
            hub: rig.hub,
            audience: { .guest },
            preferences: { AssistantPreferences(speaksAnswers: false, listensOnOpen: false, autoDismissSeconds: 1) },
            responder: rig.responder,
            speechInput: rig.input,
            speechOutput: rig.output
        )
        engine.open()
        engine.submit("night")
        await waitUntil { engine.conversation.phase == .followUps }
        #expect(engine.conversation.exchange?.answer == "Night Mode is on.")
        await waitUntil { !engine.conversation.isOpen }
    }
}
