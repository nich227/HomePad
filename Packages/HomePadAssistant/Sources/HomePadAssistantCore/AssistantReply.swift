import Foundation

/// What the model produced for one request, before any of it is trusted.
public struct AssistantModelReply: Equatable, Sendable {
    public var answer: String
    public var usedContextTags: [String]
    public var suggestedFollowUps: [String]

    public init(answer: String = "", usedContextTags: [String] = [], suggestedFollowUps: [String] = []) {
        self.answer = answer
        self.usedContextTags = usedContextTags
        self.suggestedFollowUps = suggestedFollowUps
    }
}

public enum AssistantReplyEvent: Equatable, Sendable {
    /// The whole answer so far.
    case partial(String)
    case final(AssistantModelReply)
}

/// A chip under the answer. The ones with a meaning come from what the hub just did, so they
/// are known to work. `suggested` carries the model's own words.
public enum AssistantFollowUp: Hashable, Sendable {
    case pauseTimer(String)
    case cancelTimer(String)
    case showTimers
    case nightMode(isOn: Bool)
    case accessory(name: String, isOn: Bool)
    case suggested(String)
}

/// One request and its answer, as the card shows them.
public struct AssistantExchange: Equatable, Sendable {
    public var request: String
    public var answer: String
    /// Context the answer relied on. Only items that were allowed into the prompt can be here.
    public var snippets: [AssistantContextItem]
    public var followUps: [AssistantFollowUp]

    public init(request: String, answer: String = "", snippets: [AssistantContextItem] = [], followUps: [AssistantFollowUp] = []) {
        self.request = request
        self.answer = answer
        self.snippets = snippets
        self.followUps = followUps
    }
}

public enum AssistantReplyComposer {
    /// Turns the model's reply into what the card shows. Returns nil when there is nothing to
    /// show: no answer and no action.
    public static func exchange(
        request: String,
        reply: AssistantModelReply,
        reports: [AssistantActionReport],
        context: AssistantAllowedContext,
        reportText: (AssistantActionReport) -> String
    ) -> AssistantExchange? {
        var text = answer(reply.answer)
        if text.isEmpty {
            text = answer(reports.map(reportText).joined(separator: " "))
        }
        guard !text.isEmpty else { return nil }
        return AssistantExchange(
            request: request,
            answer: text,
            snippets: Array(context.items(tagged: reply.usedContextTags).prefix(AssistantLimits.maxSnippets)),
            followUps: followUps(suggested: reply.suggestedFollowUps, reports: reports, request: request)
        )
    }

    /// Plain text on one line, without the marks a model adds for emphasis, cut to the card's limit.
    public static func answer(_ text: String) -> String {
        let plain = String(text.filter { !"*#`".contains($0) })
        return AssistantText.singleLine(plain, limit: AssistantLimits.maxAnswerCharacters)
    }

    /// What is read aloud: the first few sentences, without web addresses, short enough to
    /// follow from across a room.
    public static func spokenText(for answer: String) -> String {
        let words = answer.split(separator: " ").filter { !$0.hasPrefix("http://") && !$0.hasPrefix("https://") }
        var sentences: [String] = []
        var current: [Substring] = []
        for word in words {
            current.append(word)
            if let last = word.last, ".!?".contains(last) {
                sentences.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty {
            sentences.append(current.joined(separator: " "))
        }
        var spoken = ""
        for sentence in sentences.prefix(AssistantLimits.maxSpokenSentences) {
            let candidate = spoken.isEmpty ? sentence : spoken + " " + sentence
            guard candidate.count <= AssistantLimits.maxSpokenCharacters else { break }
            spoken = candidate
        }
        if spoken.isEmpty, let first = sentences.first {
            spoken = AssistantText.clip(first, limit: AssistantLimits.maxSpokenCharacters)
        }
        return spoken
    }

    /// At most three chips. The ones derived from what the hub just did come first, then the
    /// model's suggestions that are short, on one line, new, and not the request itself.
    public static func followUps(
        suggested: [String],
        reports: [AssistantActionReport],
        request: String
    ) -> [AssistantFollowUp] {
        var chips: [AssistantFollowUp] = []
        for chip in reports.compactMap(\.value).flatMap(derived(from:)) where !chips.contains(chip) {
            chips.append(chip)
        }
        var seen: Set<String> = [request.lowercased()]
        for suggestion in suggested {
            let text = AssistantText.singleLine(suggestion, limit: .max)
            guard text.count >= 2, text.count <= AssistantLimits.maxFollowUpCharacters else { continue }
            guard seen.insert(text.lowercased()).inserted else { continue }
            chips.append(.suggested(text))
        }
        return Array(chips.prefix(AssistantLimits.maxFollowUps))
    }

    static func derived(from value: AssistantActionValue) -> [AssistantFollowUp] {
        switch value {
        case .timerStarted(let timer):
            [.pauseTimer(timer.name), .cancelTimer(timer.name)]
        case .timerPaused(let timer):
            [.cancelTimer(timer.name), .showTimers]
        case .timerCanceled:
            [.showTimers]
        case .nightMode(let isOn):
            [.nightMode(isOn: !isOn)]
        case .accessory(let accessory):
            [.accessory(name: accessory.name, isOn: !accessory.isOn)]
        case .timers, .showing, .sceneRan, .thermostat, .weather, .pageOpened, .noteSent, .screen:
            []
        }
    }
}
