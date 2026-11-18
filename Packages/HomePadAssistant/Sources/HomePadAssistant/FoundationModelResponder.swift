import Foundation
import FoundationModels
import HomePadAssistantCore

/// The reply the model fills in. Guided generation keeps the answer, the context it relied on,
/// and the follow-ups apart, so none of them has to be parsed out of prose.
@Generable
struct GeneratedReply {
    @Guide(description: "What to say back, in one or two short sentences of plain text.")
    var answer: String
    @Guide(description: "Tags of the context lines the answer relied on, such as c1. Empty when none.", .maximumCount(3))
    var usedContext: [String]
    @Guide(description: "Up to three short things the person might ask next. Empty when none.", .maximumCount(3))
    var followUps: [String]
}

/// Answers with the language model on this device. One session lasts for one conversation:
/// `reset` drops it, and the next request starts a new one with the tools and instructions for
/// whoever is asking then.
@MainActor
final class FoundationModelResponder: AssistantResponder {
    private let model: SystemLanguageModel
    private var session: LanguageModelSession?

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) -> AsyncThrowingStream<AssistantReplyEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<AssistantReplyEvent, any Error>.makeStream()
        let task = Task {
            do {
                try await self.run(turn, toolbox: toolbox, into: continuation)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch let failure as AssistantFailure {
                continuation.finish(throwing: failure)
            } catch {
                continuation.finish(throwing: AssistantFailure(Self.kind(of: error)))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func reset() {
        session = nil
    }

    private func run(
        _ turn: AssistantTurn,
        toolbox: AssistantToolbox,
        into continuation: AsyncThrowingStream<AssistantReplyEvent, any Error>.Continuation
    ) async throws {
        guard model.isAvailable else { throw AssistantFailure.modelUnavailable }
        let session = self.session ?? LanguageModelSession(
            model: model,
            tools: AssistantTools.tools(for: turn.capabilities, toolbox: toolbox),
            instructions: Instructions(turn.instructions)
        )
        self.session = session
        let stream = session.streamResponse(
            to: turn.prompt,
            generating: GeneratedReply.self,
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: turn.maximumResponseTokens),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        var reply = AssistantModelReply()
        for try await snapshot in stream {
            let partial = snapshot.content
            reply = AssistantModelReply(
                answer: partial.answer ?? "",
                usedContextTags: partial.usedContext ?? [],
                suggestedFollowUps: partial.followUps ?? []
            )
            if !reply.answer.isEmpty {
                continuation.yield(.partial(reply.answer))
            }
        }
        try Task.checkCancellation()
        continuation.yield(.final(reply))
    }

    /// Names the framework's errors in the package's own terms. A failed tool call and a reply
    /// that does not parse are both `other`: the person can only try again.
    static func kind(of error: any Error) -> ModelErrorKind {
        switch error {
        case let error as LanguageModelError:
            switch error {
            case .contextSizeExceeded: .contextSizeExceeded
            case .guardrailViolation: .guardrailViolation
            case .refusal: .refusal
            case .rateLimited: .rateLimited
            case .unsupportedLanguageOrLocale: .unsupportedLanguage
            case .timeout: .timeout
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide: .other
            @unknown default: .other
            }
        case let error as SystemLanguageModel.Error:
            switch error {
            case .assetsUnavailable: .assetsUnavailable
            @unknown default: .other
            }
        case let error as LanguageModelSession.Error:
            switch error {
            case .concurrentRequests, .transcriptMutationWhileResponding: .concurrentRequests
            @unknown default: .other
            }
        default:
            .other
        }
    }
}

/// Answers from a fixed script, for previews and UI tests on a machine with no model. It acts
/// through the same toolbox as the model, so the hub's rules still apply.
@MainActor
public final class ScriptedAssistantResponder: AssistantResponder {
    public struct Line: Sendable {
        public var answer: String
        public var requests: [AssistantRequest]
        public var usedContextTags: [String]
        public var followUps: [String]

        public init(answer: String, requests: [AssistantRequest] = [], usedContextTags: [String] = [], followUps: [String] = []) {
            self.answer = answer
            self.requests = requests
            self.usedContextTags = usedContextTags
            self.followUps = followUps
        }
    }

    private let lines: [Line]
    private let wordDelay: Duration
    private var next = 0

    /// The lines are given in turn and start over after the last one.
    public init(lines: [Line] = ScriptedAssistantResponder.sampleLines, wordDelay: Duration = .milliseconds(60)) {
        self.lines = lines
        self.wordDelay = wordDelay
    }

    public static let sampleLines: [Line] = [
        Line(
            answer: "It is sunny and 68 degrees. You have the dentist tomorrow at nine.",
            requests: [.weather],
            usedContextTags: ["c1", "c2"],
            followUps: ["What about tomorrow?", "Start a ten minute timer"]
        ),
        Line(answer: "Your timer is running.", requests: [.startTimer(name: nil, seconds: 600)]),
        Line(answer: "Night Mode is on.", requests: [.setNightMode(isOn: true)]),
    ]

    public func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) -> AsyncThrowingStream<AssistantReplyEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<AssistantReplyEvent, any Error>.makeStream()
        guard !lines.isEmpty else {
            continuation.finish(throwing: AssistantFailure.modelUnavailable)
            return stream
        }
        let line = lines[next % lines.count]
        next += 1
        let wordDelay = wordDelay
        let task = Task {
            for request in line.requests {
                _ = await toolbox.perform(request)
            }
            var spoken: [Substring] = []
            for word in line.answer.split(separator: " ") {
                guard (try? await Task.sleep(for: wordDelay)) != nil else {
                    continuation.finish()
                    return
                }
                spoken.append(word)
                continuation.yield(.partial(spoken.joined(separator: " ")))
            }
            continuation.yield(.final(AssistantModelReply(
                answer: line.answer,
                usedContextTags: line.usedContextTags,
                suggestedFollowUps: line.followUps
            )))
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func reset() {
        next = 0
    }
}
