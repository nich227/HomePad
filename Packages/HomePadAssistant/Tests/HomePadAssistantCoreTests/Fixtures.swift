import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistantCore

enum Fixtures {
    static let erica = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let danny = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static let guest = AssistantAudience.guest
    static let manualErica = AssistantAudience(memberID: erica, memberName: "Erica", isRecognized: false, isPersonalContentUnlocked: false)
    static let recognizedLockedErica = AssistantAudience(memberID: erica, memberName: "Erica", isRecognized: true, isPersonalContentUnlocked: false)
    static let unlockedErica = AssistantAudience(memberID: erica, memberName: "Erica", isRecognized: true, isPersonalContentUnlocked: true)
    static let unlockedDanny = AssistantAudience(memberID: danny, memberName: "Danny", isRecognized: true, isPersonalContentUnlocked: true)

    static let timerItem = AssistantContextItem(id: "t1", kind: .timer, title: "Pasta", detail: "9 minutes left")
    static let weatherItem = AssistantContextItem(id: "w1", kind: .weather, title: "Sunny", detail: "68 degrees")
    static let ericaEvent = AssistantContextItem(id: "e1", kind: .calendarEvent, ownerID: erica, title: "Dentist", detail: "Tomorrow 9:00")
    static let ericaReminder = AssistantContextItem(id: "r2", kind: .reminder, ownerID: erica, title: "Water plants", detail: "Due today")
    static let dannyReminder = AssistantContextItem(id: "r1", kind: .reminder, ownerID: danny, title: "Buy milk")
    static let ownerlessEvent = AssistantContextItem(id: "e2", kind: .calendarEvent, title: "Secret party")
    static let ericaPlaylist = AssistantContextItem(id: "p1", kind: .playlist, ownerID: erica, title: "Running mix")
    static let allItems = [timerItem, weatherItem, ericaEvent, ericaReminder, dannyReminder, ownerlessEvent, ericaPlaylist]
    static let personalMarkers = ["Dentist", "Water plants", "Due today", "Buy milk", "Secret party", "Running mix"]

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func timer(_ name: String = "Pasta", remaining: TimeInterval = 600, isPaused: Bool = false) -> AssistantTimer {
        AssistantTimer(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!, name: name, remaining: remaining, isPaused: isPaused)
    }
}

/// Records every call and answers from values the test sets.
@MainActor
final class FakeActions: AssistantActions {
    private(set) var calls: [String] = []
    var failure: AssistantActionError?
    var timerList: [AssistantTimer] = []
    var weather = "Sunny and 68"
    var screen = "Clock face showing 2:05"

    private func answer<Value>(_ call: String, _ value: Value) -> Result<Value, AssistantActionError> {
        calls.append(call)
        if let failure { return .failure(failure) }
        return .success(value)
    }

    func startTimer(name: String?, duration: TimeInterval) async -> Result<AssistantTimer, AssistantActionError> {
        answer("startTimer \(name ?? "nil") \(Int(duration))", Fixtures.timer(name ?? "Timer", remaining: duration))
    }

    func pauseTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        answer("pauseTimer \(name ?? "nil")", Fixtures.timer(name ?? "Timer", remaining: 120, isPaused: true))
    }

    func cancelTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        answer("cancelTimer \(name ?? "nil")", Fixtures.timer(name ?? "Timer"))
    }

    func timers() async -> Result<[AssistantTimer], AssistantActionError> {
        answer("timers", timerList)
    }

    func show(named name: String) async -> Result<AssistantDestination, AssistantActionError> {
        answer("show \(name)", name == "Weather" ? .app(name) : .face(name))
    }

    func setNightMode(_ isOn: Bool) async -> Result<Bool, AssistantActionError> {
        answer("nightMode \(isOn)", isOn)
    }

    func runScene(named name: String) async -> Result<String, AssistantActionError> {
        answer("runScene \(name)", name)
    }

    func setThermostat(targetCelsius: Double) async -> Result<AssistantThermostat, AssistantActionError> {
        answer("thermostat \(targetCelsius)", AssistantThermostat(name: "Hallway", targetCelsius: targetCelsius))
    }

    func setAccessory(named name: String, isOn: Bool) async -> Result<AssistantAccessory, AssistantActionError> {
        answer("accessory \(name) \(isOn)", AssistantAccessory(name: name, isOn: isOn))
    }

    func weatherSummary() async -> Result<String, AssistantActionError> {
        answer("weather", weather)
    }

    func openWebPage(_ url: URL) async -> Result<URL, AssistantActionError> {
        answer("openWebPage \(url.absoluteString)", url)
    }

    func sendHouseholdNote(_ text: String) async -> Result<AssistantNoteReceipt, AssistantActionError> {
        answer("note \(text)", AssistantNoteReceipt(recipientCount: 2))
    }

    func screenSummary() async -> Result<String, AssistantActionError> {
        answer("screen", screen)
    }
}

@MainActor
final class FakeHub: AssistantHubContext {
    var hubState = AssistantHubState(hubName: "Kitchen", screenTitle: "Clock face", isNightMode: false, usesFahrenheit: true)
    var items: [AssistantContextItem] = Fixtures.allItems
    /// When set, `contextItems` waits here until the test lets it go.
    var gate: AsyncStream<Void>?
    private(set) var contextRequests = 0

    func contextItems() async -> [AssistantContextItem] {
        contextRequests += 1
        if let gate {
            for await _ in gate { break }
        }
        return items
    }
}

/// Plays back one scripted reply per call, and keeps the turns it was given.
@MainActor
final class FakeResponder: AssistantResponder {
    enum Step: Sendable {
        case events([AssistantReplyEvent])
        case fail(any Error)
        /// Performs a request through the toolbox, then replies.
        case act([AssistantRequest], then: [AssistantReplyEvent])
        /// Performs requests through the toolbox, then fails.
        case actThenFail([AssistantRequest], any Error)
        /// Yields the events and then never finishes.
        case hang([AssistantReplyEvent])
        /// Waits, and throws when the request is canceled.
        case throwOnCancel
    }

    var script: [Step] = []
    private(set) var turns: [AssistantTurn] = []
    private(set) var resets = 0
    private(set) var toolReports: [AssistantActionReport] = []

    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) -> AsyncThrowingStream<AssistantReplyEvent, any Error> {
        turns.append(turn)
        let step = script.isEmpty ? Step.events([.final(AssistantModelReply(answer: "Done."))]) : script.removeFirst()
        if case .throwOnCancel = step {
            return AsyncThrowingStream {
                try await Task.sleep(for: .seconds(600))
                return nil
            }
        }
        let (stream, continuation) = AsyncThrowingStream<AssistantReplyEvent, any Error>.makeStream()
        let task = Task {
            switch step {
            case .events(let events):
                events.forEach { continuation.yield($0) }
                continuation.finish()
            case .fail(let error):
                continuation.finish(throwing: error)
            case .act(let requests, let events):
                for request in requests {
                    self.toolReports.append(await toolbox.perform(request))
                }
                events.forEach { continuation.yield($0) }
                continuation.finish()
            case .actThenFail(let requests, let error):
                for request in requests {
                    self.toolReports.append(await toolbox.perform(request))
                }
                continuation.finish(throwing: error)
            case .hang(let events):
                events.forEach { continuation.yield($0) }
            case .throwOnCancel:
                break
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func reset() {
        resets += 1
    }
}

@MainActor
final class FakeSpeechInput: AssistantSpeechInput {
    private(set) var starts = 0
    private(set) var stops = 0
    /// When true, the stream waits and throws when listening is canceled.
    var throwsOnCancel = false
    private var continuation: AsyncThrowingStream<AssistantTranscript, any Error>.Continuation?

    func transcripts() -> AsyncThrowingStream<AssistantTranscript, any Error> {
        starts += 1
        if throwsOnCancel {
            return AsyncThrowingStream {
                try await Task.sleep(for: .seconds(600))
                return nil
            }
        }
        let (stream, continuation) = AsyncThrowingStream<AssistantTranscript, any Error>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() {
        stops += 1
    }

    func hear(_ text: String, isFinal: Bool = false) {
        continuation?.yield(AssistantTranscript(text: text, isFinal: isFinal))
    }

    func end(throwing error: (any Error)? = nil) {
        continuation?.finish(throwing: error)
    }
}

@MainActor
final class FakeSpeechOutput: AssistantSpeechOutput {
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    /// When true, `speak` does not return until `finish` or `stop`.
    var holds = false
    private var waiting: CheckedContinuation<Void, Never>?

    func speak(_ text: String) async {
        spoken.append(text)
        if holds {
            await withCheckedContinuation { waiting = $0 }
        }
    }

    func stop() {
        stops += 1
        finish()
    }

    func finish() {
        waiting?.resume()
        waiting = nil
    }
}

@MainActor
final class TestClock {
    var date = Fixtures.start

    func advance(_ seconds: TimeInterval) {
        date += seconds
    }
}

struct TestError: Error {}

/// Lets the main actor's other tasks run until the condition holds.
@MainActor
func waitUntil(_ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<5_000 where !condition() {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition(), comment, sourceLocation: sourceLocation)
}
