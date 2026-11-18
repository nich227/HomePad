import Foundation
import Testing
@testable import HomePadAssistantCore

private struct Machine {
    var conversation = AssistantConversation()
    var now = Fixtures.start
    var preferences = AssistantPreferences()

    init(listensOnOpen: Bool = false, speaksAnswers: Bool = true, autoDismissSeconds: Int = 30, opened: Bool = true) {
        preferences = AssistantPreferences(speaksAnswers: speaksAnswers, listensOnOpen: listensOnOpen, autoDismissSeconds: autoDismissSeconds)
        if opened {
            _ = send(.open)
        }
    }

    @discardableResult
    mutating func send(_ event: AssistantConversation.Event, after seconds: TimeInterval = 0) -> [AssistantConversation.Effect] {
        now += seconds
        return conversation.handle(event, at: now, preferences: preferences)
    }

    var phase: AssistantConversation.Phase { conversation.phase }
}

@Suite struct ConversationTests {
    private let answer = AssistantExchange(request: "What time is it?", answer: "It is five past two. Anything else?", followUps: [.showTimers])

    @Test func handle_whenClosed_thenIgnoresEverythingButOpen() {
        var machine = Machine(opened: false)
        #expect(machine.send(.submit("hello")).isEmpty)
        #expect(machine.send(.microphone).isEmpty)
        #expect(machine.send(.dismiss).isEmpty)
        #expect(!machine.conversation.isOpen)
        #expect(machine.send(.open).isEmpty)
        #expect(machine.conversation.isOpen)
        #expect(machine.phase == .idle)
        #expect(machine.send(.open).isEmpty)
    }

    @Test func open_whenTheAssistantIsTurnedOff_thenStaysClosed() {
        var machine = Machine(opened: false)
        machine.preferences.isEnabled = false
        #expect(machine.send(.open).isEmpty)
        #expect(!machine.conversation.isOpen)
    }

    @Test func open_whenListenOnOpen_thenStartsListening() {
        var machine = Machine(listensOnOpen: true, opened: false)
        #expect(machine.send(.open) == [.startListening])
        #expect(machine.phase == .listening)
        #expect(machine.conversation.glowActivity == .listening)
    }

    @Test func tick_whenNothingIsHeard_thenFailsAfterTheNoSpeechTimeout() {
        var machine = Machine(listensOnOpen: true)
        #expect(machine.send(.tick, after: AssistantLimits.noSpeechTimeout - 0.1).isEmpty)
        #expect(machine.send(.tick, after: 0.1) == [.stopListening])
        #expect(machine.phase == .failed(.noSpeech))
    }

    @Test func tick_whenSpeechPauses_thenSendsWhatWasHeard() {
        var machine = Machine(listensOnOpen: true)
        #expect(machine.send(.heard("set a"), after: 7).isEmpty)
        #expect(machine.send(.heard("set a timer"), after: 2).isEmpty)
        #expect(machine.conversation.heard == "set a timer")
        #expect(machine.send(.tick, after: 1).isEmpty)
        #expect(machine.send(.tick, after: 0.7) == [.stopListening, .generate("set a timer")])
        #expect(machine.phase == .thinking)
        #expect(machine.conversation.exchange == AssistantExchange(request: "set a timer"))
        #expect(machine.conversation.heard.isEmpty)
        #expect(machine.conversation.glowActivity == .thinking)
    }

    @Test func tick_whenOnlyBlankSpeechWasHeard_thenGoesIdle() {
        var machine = Machine(listensOnOpen: true)
        machine.send(.heard("   "))
        #expect(machine.send(.tick, after: 2) == [.stopListening])
        #expect(machine.phase == .idle)
    }

    @Test func heardFinal_whenTextOrNothing_thenSendsItOrFails() {
        var machine = Machine(listensOnOpen: true)
        #expect(machine.send(.heardFinal("what time is it")) == [.stopListening, .generate("what time is it")])
        #expect(machine.send(.heardFinal("late")).isEmpty)
        #expect(machine.send(.heard("late")).isEmpty)

        var silent = Machine(listensOnOpen: true)
        #expect(silent.send(.heardFinal("")) == [.stopListening])
        #expect(silent.phase == .failed(.noSpeech))
    }

    @Test func microphone_whenListening_thenEndsListeningAndSendsWhatWasHeard() {
        var machine = Machine(listensOnOpen: true)
        #expect(machine.send(.microphone) == [.stopListening])
        #expect(machine.phase == .idle)
        #expect(machine.send(.microphone) == [.startListening])
        machine.send(.heard("lights on"))
        #expect(machine.send(.microphone) == [.stopListening, .generate("lights on")])
    }

    @Test func microphone_whenAnsweringOrSpeaking_thenStopsThatFirst() {
        var machine = Machine()
        machine.send(.submit("hello"))
        machine.send(.draft("Hi"))
        #expect(machine.send(.microphone) == [.cancelGeneration, .startListening])
        #expect(machine.conversation.exchange == nil)

        var speaking = Machine()
        speaking.send(.submit("hello"))
        #expect(speaking.send(.completed(answer)) == [.speak("It is five past two. Anything else?")])
        #expect(speaking.conversation.isSpeaking)
        #expect(speaking.send(.microphone) == [.stopSpeaking, .startListening])
        #expect(!speaking.conversation.isSpeaking)
    }

    @Test func submit_whenBlankOrBusy_thenIgnoredOrReplacesTheRequest() {
        var machine = Machine()
        #expect(machine.send(.submit(" \n ")).isEmpty)
        #expect(machine.send(.submit("first\nquestion")) == [.generate("first question")])
        #expect(machine.send(.submit("second")) == [.cancelGeneration, .generate("second")])
        #expect(machine.conversation.exchange?.request == "second")
        let long = machine.send(.submit(String(repeating: "word ", count: 200)))
        guard case .generate(let request) = long.last else {
            Issue.record("no request")
            return
        }
        #expect(request.count <= AssistantLimits.maxRequestCharacters)
    }

    @Test func draft_whenResponding_thenShowsTheTextAsItStreams() {
        var machine = Machine()
        #expect(machine.send(.draft("stray")).isEmpty)
        machine.send(.submit("hello"))
        #expect(machine.send(.draft("Hi")).isEmpty)
        #expect(machine.phase == .answering)
        #expect(machine.conversation.exchange?.answer == "Hi")
        #expect(machine.conversation.glowActivity == .answering)
        machine.send(.draft("Hi there"))
        #expect(machine.conversation.exchange?.answer == "Hi there")
    }

    @Test func completed_whenSpeakAnswersIsOnOrOff_thenSpeaksOrStaysQuiet() {
        var machine = Machine()
        #expect(machine.send(.completed(answer)).isEmpty)
        machine.send(.submit("What time is it?"))
        #expect(machine.send(.completed(answer)) == [.speak("It is five past two. Anything else?")])
        #expect(machine.phase == .followUps)
        #expect(machine.conversation.exchange == answer)
        #expect(machine.conversation.glowActivity == .idle)

        var quiet = Machine(speaksAnswers: false)
        quiet.send(.submit("What time is it?"))
        #expect(quiet.send(.completed(answer)).isEmpty)
        #expect(!quiet.conversation.isSpeaking)
    }

    @Test func failed_whenBusy_thenStopsAndShowsTheFailure() {
        var machine = Machine()
        #expect(machine.send(.failed(.refused)).isEmpty)
        machine.send(.submit("hello"))
        #expect(machine.send(.failed(.refused)) == [.cancelGeneration])
        #expect(machine.phase == .failed(.refused))

        var listening = Machine(listensOnOpen: true)
        #expect(listening.send(.failed(.microphoneNotPermitted)) == [.stopListening])
        #expect(listening.phase == .failed(.microphoneNotPermitted))
    }

    @Test func cancel_whenAnswering_thenStopsAndClearsTheCard() {
        var machine = Machine()
        machine.send(.submit("hello"))
        machine.send(.draft("Hi"))
        #expect(machine.send(.cancel) == [.cancelGeneration])
        #expect(machine.phase == .idle)
        #expect(machine.conversation.exchange == nil)
        #expect(machine.conversation.isOpen)
    }

    @Test func tick_whenTheModelStalls_thenTimesOut() {
        var machine = Machine()
        machine.send(.submit("hello"))
        #expect(machine.send(.tick, after: 29).isEmpty)
        machine.send(.draft("Hi"), after: 0.5)
        #expect(machine.send(.tick, after: 29).isEmpty)
        #expect(machine.send(.tick, after: 1) == [.cancelGeneration])
        #expect(machine.phase == .failed(.timedOut))
    }

    @Test func tick_whenNobodyTouchesTheAnswer_thenClosesAfterSpeakingEnds() {
        var machine = Machine(autoDismissSeconds: 15)
        machine.send(.submit("hello"))
        machine.send(.completed(answer))
        #expect(machine.send(.tick, after: 60).isEmpty)
        machine.send(.spoken)
        #expect(machine.send(.tick, after: 14).isEmpty)
        machine.send(.touched)
        #expect(machine.send(.tick, after: 14).isEmpty)
        #expect(machine.send(.tick, after: 1) == [.resetSession, .close])
        #expect(machine.conversation == AssistantConversation())
    }

    @Test func tick_whenAutoDismissIsOff_thenStaysOpen() {
        var machine = Machine(autoDismissSeconds: 0)
        #expect(machine.send(.tick, after: 10_000).isEmpty)
        #expect(machine.conversation.isOpen)
    }

    @Test func dismiss_whenListeningOrSpeaking_thenReleasesEverythingAndForgets() {
        var machine = Machine(listensOnOpen: true)
        #expect(machine.send(.dismiss) == [.stopListening, .resetSession, .close])
        #expect(!machine.conversation.isOpen)

        var speaking = Machine()
        speaking.send(.submit("hello"))
        speaking.send(.completed(answer))
        #expect(speaking.send(.dismiss) == [.stopSpeaking, .resetSession, .close])
        #expect(speaking.conversation.exchange == nil)
    }
}
