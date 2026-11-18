import Foundation
import Observation

/// Answers one request with the language model. The live one wraps a model session and keeps
/// it for the whole conversation.
@MainActor
public protocol AssistantResponder: AnyObject {
    /// Streams the reply. The model's tools act through `toolbox`. Throws `AssistantFailure`.
    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) -> AsyncThrowingStream<AssistantReplyEvent, any Error>
    /// Drops the session and everything said in it.
    func reset()
}

public struct AssistantTranscript: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

@MainActor
public protocol AssistantSpeechInput: AnyObject {
    /// Starts the microphone and yields what has been heard so far each time it changes. The
    /// microphone stops when the stream ends, is dropped, or `stop` is called. Throws
    /// `AssistantFailure`.
    func transcripts() -> AsyncThrowingStream<AssistantTranscript, any Error>
    func stop()
}

@MainActor
public protocol AssistantSpeechOutput: AnyObject {
    /// Returns when the text has been spoken or speaking was stopped.
    func speak(_ text: String) async
    func stop()
}

/// What the hub tells the Assistant about itself.
@MainActor
public protocol AssistantHubContext: AnyObject {
    var hubState: AssistantHubState { get }
    /// Facts the hub can offer for an answer. The Assistant drops whatever the person in front
    /// of the hub may not see before any of it reaches the model.
    func contextItems() async -> [AssistantContextItem]
}

/// Where the model's tools send their requests during one turn.
@MainActor
public final class AssistantToolbox {
    private let router: AssistantRouter
    public private(set) var reports: [AssistantActionReport] = []

    init(router: AssistantRouter) {
        self.router = router
    }

    public func perform(_ request: AssistantRequest) async -> AssistantActionReport {
        guard reports.count < AssistantLimits.maxActionsPerTurn else {
            return AssistantActionReport(request: request, result: .failure(.limitReached))
        }
        let report = await router.perform(request)
        reports.append(report)
        return report
    }

    func beginTurn() {
        reports = []
    }
}

/// Runs the Assistant: listens, asks the model, speaks, and keeps the conversation's state for
/// the overlay to draw. It stays alive while the overlay is open.
@MainActor
@Observable
public final class AssistantEngine {
    public private(set) var conversation = AssistantConversation()

    @ObservationIgnored private let router: AssistantRouter
    @ObservationIgnored private let toolbox: AssistantToolbox
    @ObservationIgnored private let hub: any AssistantHubContext
    @ObservationIgnored private let audience: @MainActor () -> AssistantAudience
    @ObservationIgnored private let preferences: @MainActor () -> AssistantPreferences
    @ObservationIgnored private let responder: any AssistantResponder
    @ObservationIgnored private let speechInput: any AssistantSpeechInput
    @ObservationIgnored private let speechOutput: any AssistantSpeechOutput
    @ObservationIgnored private let reportText: @MainActor (AssistantActionReport) -> String
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void

    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var speakTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Each count names the latest run of its kind. A task that finds a newer count was replaced
    /// and must not touch the conversation.
    @ObservationIgnored private var listenRun = 0
    @ObservationIgnored private var generationRun = 0
    @ObservationIgnored private var speakRun = 0
    /// Who the model's session has been talking with.
    @ObservationIgnored private var sessionAudience: AssistantAudience?
    /// Set once the session has been given personal context, to the person it was given for.
    @ObservationIgnored private var personalContextAudience: AssistantAudience?

    public init(
        actions: any AssistantActions,
        hub: any AssistantHubContext,
        audience: @escaping @MainActor () -> AssistantAudience,
        preferences: @escaping @MainActor () -> AssistantPreferences,
        responder: any AssistantResponder,
        speechInput: any AssistantSpeechInput,
        speechOutput: any AssistantSpeechOutput,
        reportText: @escaping @MainActor (AssistantActionReport) -> String = { $0.modelText },
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        let router = AssistantRouter(actions: actions, audience: audience, usesFahrenheit: { hub.hubState.usesFahrenheit })
        self.router = router
        toolbox = AssistantToolbox(router: router)
        self.hub = hub
        self.audience = audience
        self.preferences = preferences
        self.responder = responder
        self.speechInput = speechInput
        self.speechOutput = speechOutput
        self.reportText = reportText
        self.calendar = calendar
        self.now = now
        self.sleep = sleep
    }

    /// Whether the overlay may be shown at all.
    public var isEnabled: Bool {
        preferences().isEnabled
    }

    public func open() {
        let wasOpen = conversation.isOpen
        send(.open)
        if !wasOpen, conversation.isOpen {
            startTicking()
        }
    }

    /// The microphone button.
    public func toggleListening() {
        send(.microphone)
    }

    public func submit(_ text: String) {
        send(.submit(text))
    }

    /// Call when the person touches the card or types, so the overlay does not close on them.
    public func noteInteraction() {
        send(.touched)
    }

    /// Stops listening, answering, and speaking, and keeps the overlay open.
    public func cancel() {
        send(.cancel)
    }

    /// Closes the overlay, releases the microphone, and forgets the conversation.
    public func dismiss() {
        send(.dismiss)
    }

    /// Performs one request under the same rules as the model's tools, without the model.
    public func perform(_ request: AssistantRequest) async -> AssistantActionReport {
        await router.perform(request)
    }

    /// Advances timeouts. Runs twice a second while the overlay is open.
    public func tick() {
        // A session that holds one person's calendar or reminders must not keep answering once
        // someone else, or nobody, is in front of the hub.
        if let personalContextAudience, personalContextAudience != audience() {
            send(.dismiss)
            return
        }
        send(.tick)
    }

    private func send(_ event: AssistantConversation.Event) {
        let effects = conversation.handle(event, at: now(), preferences: preferences())
        for effect in effects {
            run(effect)
        }
    }

    private func run(_ effect: AssistantConversation.Effect) {
        switch effect {
        case .startListening:
            startListening()
        case .stopListening:
            listenRun += 1
            listenTask?.cancel()
            listenTask = nil
            speechInput.stop()
        case .generate(let request):
            generationRun += 1
            let run = generationRun
            generationTask = Task { await self.generate(request, run: run) }
        case .cancelGeneration:
            generationRun += 1
            generationTask?.cancel()
            generationTask = nil
        case .speak(let text):
            speakRun += 1
            let run = speakRun
            speakTask = Task {
                await self.speechOutput.speak(text)
                if run == self.speakRun {
                    self.send(.spoken)
                }
            }
        case .stopSpeaking:
            speakRun += 1
            speakTask?.cancel()
            speakTask = nil
            speechOutput.stop()
        case .resetSession:
            responder.reset()
            sessionAudience = nil
            personalContextAudience = nil
        case .close:
            tickTask?.cancel()
            tickTask = nil
        }
    }

    private func startTicking() {
        let sleep = self.sleep
        tickTask = Task {
            while !Task.isCancelled {
                await sleep(AssistantLimits.tickInterval)
                if !Task.isCancelled {
                    self.tick()
                }
            }
        }
    }

    private func startListening() {
        listenRun += 1
        let run = listenRun
        let transcripts = speechInput.transcripts()
        listenTask = Task {
            do {
                for try await transcript in transcripts where run == self.listenRun {
                    self.send(transcript.isFinal ? .heardFinal(transcript.text) : .heard(transcript.text))
                }
                if run == self.listenRun {
                    self.send(.heardFinal(self.conversation.heard))
                }
            } catch {
                if run == self.listenRun {
                    self.send(.failed(AssistantFailure(error)))
                }
            }
        }
    }

    private func generate(_ request: String, run: Int) async {
        let audience = audience()
        if let sessionAudience, sessionAudience != audience {
            responder.reset()
            personalContextAudience = nil
        }
        sessionAudience = audience
        let items = await hub.contextItems()
        guard run == generationRun else { return }
        let context = AssistantPolicy.allowedContext(items, audience: audience, usesPersonalContext: preferences().usesPersonalContext)
        let turn = AssistantPrompt.turn(
            request: request,
            audience: audience,
            hubState: hub.hubState,
            context: context,
            now: now(),
            calendar: calendar
        )
        if await attempt(request, turn: turn, context: context, audience: audience, run: run, mayRetry: true) {
            _ = await attempt(request, turn: turn, context: context, audience: audience, run: run, mayRetry: false)
        }
    }

    /// Asks the model once. Returns true when the request should be asked again in a fresh
    /// session.
    private func attempt(
        _ request: String,
        turn: AssistantTurn,
        context: AssistantAllowedContext,
        audience: AssistantAudience,
        run: Int,
        mayRetry: Bool
    ) async -> Bool {
        toolbox.beginTurn()
        if context.containsPersonalItems {
            personalContextAudience = audience
        }
        do {
            var reply = AssistantModelReply()
            for try await event in responder.respond(to: turn, toolbox: toolbox) where run == generationRun {
                switch event {
                case .partial(let text):
                    reply.answer = text
                    send(.draft(AssistantReplyComposer.answer(text)))
                case .final(let final):
                    reply = final
                }
            }
            guard run == generationRun else { return false }
            let exchange = AssistantReplyComposer.exchange(
                request: request,
                reply: reply,
                reports: toolbox.reports,
                context: context,
                reportText: reportText
            )
            if let exchange {
                send(.completed(exchange))
            } else {
                send(.failed(.unknown))
            }
            return false
        } catch {
            guard run == generationRun else { return false }
            let failure = AssistantFailure(error)
            if failure == .contextTooLong {
                // The session is past repair. A fresh one can take the request again, but only
                // when nothing was done yet, so that no action runs twice.
                responder.reset()
                personalContextAudience = nil
                if mayRetry, toolbox.reports.isEmpty {
                    return true
                }
            }
            send(.failed(failure))
            return false
        }
    }
}
