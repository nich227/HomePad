import Foundation

/// The overlay's state: what the Assistant is doing and what the card shows. It decides, and
/// `AssistantEngine` carries out the effects it returns.
public struct AssistantConversation: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case listening
        case thinking
        /// Text is streaming in.
        case answering
        /// The answer is complete and its follow-up chips show.
        case followUps
        case failed(AssistantFailure)
    }

    public enum Event: Equatable, Sendable {
        case open
        /// The microphone button: starts listening, or ends it and sends what was heard.
        case microphone
        case heard(String)
        /// The recognizer finished on its own.
        case heardFinal(String)
        case submit(String)
        case draft(String)
        case completed(AssistantExchange)
        case failed(AssistantFailure)
        /// The spoken answer finished.
        case spoken
        /// The person touched the card or typed.
        case touched
        /// Stop what is happening and keep the overlay open.
        case cancel
        case tick
        case dismiss
    }

    public enum Effect: Equatable, Sendable {
        case startListening
        case stopListening
        case generate(String)
        case cancelGeneration
        case speak(String)
        case stopSpeaking
        /// Forget the conversation, so nothing said in it reaches the next one.
        case resetSession
        case close
    }

    public private(set) var isOpen = false
    public private(set) var phase = Phase.idle
    /// What the recognizer has heard so far while listening.
    public private(set) var heard = ""
    public private(set) var exchange: AssistantExchange?
    public private(set) var isSpeaking = false
    private var phaseSince = Date.distantPast
    /// The last sign of life: speech heard, text streamed, a touch, or the end of speaking.
    private var lastActivity = Date.distantPast

    public init() {}

    public var glowActivity: EdgeGlow.Activity {
        switch phase {
        case .listening: .listening
        case .thinking: .thinking
        case .answering: .answering
        case .idle, .followUps, .failed: .idle
        }
    }

    public mutating func handle(_ event: Event, at now: Date, preferences: AssistantPreferences) -> [Effect] {
        guard isOpen || event == .open else { return [] }
        switch event {
        case .open:
            guard !isOpen, preferences.isEnabled else { return [] }
            isOpen = true
            enter(.idle, at: now)
            return preferences.listensOnOpen ? beginListening(at: now) : []
        case .microphone:
            return phase == .listening ? endListening(at: now, heardNothing: .idle) : beginListening(at: now)
        case .heard(let text):
            guard phase == .listening else { return [] }
            heard = text
            lastActivity = now
            return []
        case .heardFinal(let text):
            guard phase == .listening else { return [] }
            heard = text
            return endListening(at: now, heardNothing: .failed(.noSpeech))
        case .submit(let text):
            return submit(text, at: now)
        case .draft(let text):
            guard isResponding else { return [] }
            phase = .answering
            exchange?.answer = text
            lastActivity = now
            return []
        case .completed(let finished):
            guard isResponding else { return [] }
            exchange = finished
            enter(.followUps, at: now)
            let spoken = AssistantReplyComposer.spokenText(for: finished.answer)
            guard preferences.speaksAnswers, !spoken.isEmpty else { return [] }
            isSpeaking = true
            return [.speak(spoken)]
        case .failed(let failure):
            guard phase == .listening || isResponding else { return [] }
            let effects = stopActivity()
            enter(.failed(failure), at: now)
            return effects
        case .spoken:
            isSpeaking = false
            lastActivity = now
            return []
        case .touched:
            lastActivity = now
            return []
        case .cancel:
            let effects = stopActivity()
            exchange = nil
            heard = ""
            enter(.idle, at: now)
            return effects
        case .tick:
            return tick(at: now, preferences: preferences)
        case .dismiss:
            return close()
        }
    }

    private var isResponding: Bool {
        phase == .thinking || phase == .answering
    }

    private mutating func enter(_ phase: Phase, at now: Date) {
        self.phase = phase
        phaseSince = now
        lastActivity = now
    }

    /// Ends whatever uses the microphone, the model, or the speaker.
    private mutating func stopActivity() -> [Effect] {
        var effects: [Effect] = []
        if phase == .listening {
            effects.append(.stopListening)
        }
        if isResponding {
            effects.append(.cancelGeneration)
        }
        if isSpeaking {
            isSpeaking = false
            effects.append(.stopSpeaking)
        }
        return effects
    }

    private mutating func beginListening(at now: Date) -> [Effect] {
        let effects = stopActivity()
        exchange = nil
        heard = ""
        enter(.listening, at: now)
        return effects + [.startListening]
    }

    private mutating func endListening(at now: Date, heardNothing: Phase) -> [Effect] {
        let text = heard
        let effects = stopActivity()
        heard = ""
        enter(heardNothing, at: now)
        return effects + submit(text, at: now)
    }

    private mutating func submit(_ text: String, at now: Date) -> [Effect] {
        let request = AssistantText.singleLine(text, limit: AssistantLimits.maxRequestCharacters)
        guard !request.isEmpty else { return [] }
        let effects = stopActivity()
        heard = ""
        exchange = AssistantExchange(request: request)
        enter(.thinking, at: now)
        return effects + [.generate(request)]
    }

    private mutating func tick(at now: Date, preferences: AssistantPreferences) -> [Effect] {
        let quiet = now.timeIntervalSince(lastActivity)
        switch phase {
        case .listening:
            if heard.isEmpty {
                guard now.timeIntervalSince(phaseSince) >= AssistantLimits.noSpeechTimeout else { return [] }
                let effects = stopActivity()
                enter(.failed(.noSpeech), at: now)
                return effects
            }
            guard quiet >= AssistantLimits.endOfSpeechPause else { return [] }
            return endListening(at: now, heardNothing: .idle)
        case .thinking, .answering:
            guard quiet >= AssistantLimits.responseTimeout else { return [] }
            let effects = stopActivity()
            enter(.failed(.timedOut), at: now)
            return effects
        case .idle, .followUps, .failed:
            guard !isSpeaking, let limit = preferences.autoDismissAfter, quiet >= limit else { return [] }
            return close()
        }
    }

    private mutating func close() -> [Effect] {
        let effects = stopActivity()
        self = AssistantConversation()
        return effects + [.resetSession, .close]
    }
}
