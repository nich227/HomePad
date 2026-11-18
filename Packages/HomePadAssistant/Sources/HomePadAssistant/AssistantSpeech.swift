import AVFoundation
import Foundation
import HomePadAssistantCore
import Speech

/// Listens through the microphone and recognizes speech on this device only. A request that
/// would need Apple's servers is never made: where the device cannot recognize the language by
/// itself, listening fails and the person types instead.
///
/// The microphone runs from `transcripts()` until the stream ends or `stop()` is called, and
/// at no other time.
@MainActor
final class OnDeviceSpeechInput: AssistantSpeechInput {
    private let locale: Locale
    private var run = 0
    private var setup: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<AssistantTranscript, any Error>.Continuation?
    private var interruptionObserver: NotificationCenter.ObservationToken?
    private var heardSomething = false
    private var holdsAudioSession = false

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcripts() -> AsyncThrowingStream<AssistantTranscript, any Error> {
        stop()
        let run = self.run
        let (stream, continuation) = AsyncThrowingStream<AssistantTranscript, any Error>.makeStream()
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                // A newer stream has taken over by the time an old one reports its end.
                if self?.run == run {
                    self?.stop()
                }
            }
        }
        setup = Task { await self.start(run) }
        return stream
    }

    func stop() {
        run += 1
        setup?.cancel()
        setup = nil
        recognition?.cancel()
        recognition = nil
        request?.endAudio()
        request = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        continuation?.finish()
        continuation = nil
        heardSomething = false
        if holdsAudioSession {
            holdsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func fail(_ kind: SpeechErrorKind, run: Int) {
        guard run == self.run else { return }
        continuation?.finish(throwing: AssistantFailure(kind))
        continuation = nil
        stop()
    }

    private func start(_ run: Int) async {
        guard await Self.speechIsAuthorized() else { return fail(.speechDenied, run: run) }
        guard await AVAudioApplication.requestRecordPermission() else { return fail(.microphoneDenied, run: run) }
        guard run == self.run else { return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return fail(.recognizerUnavailable, run: run)
        }
        guard recognizer.supportsOnDeviceRecognition else { return fail(.onDeviceUnsupported, run: run) }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let audioEngine = AVAudioEngine()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            holdsAudioSession = true
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return fail(.recognizerUnavailable, run: run) }
            try Self.installTap(on: input, format: format, feeding: RequestBox(request: request))
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            // Starting audio fails for reasons the person cannot act on beyond trying again.
            return fail(.other, run: run)
        }
        self.request = request
        self.audioEngine = audioEngine
        observeInterruptions(run: run)
        recognition = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, errorCode in
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, errorCode: errorCode, run: run)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, errorCode: Int?, run: Int) {
        guard run == self.run else { return }
        if let text, !text.isEmpty {
            heardSomething = true
            continuation?.yield(AssistantTranscript(text: text, isFinal: isFinal))
        }
        if let errorCode {
            // After speech was heard, an error only means the recognizer is done. Ending the
            // stream lets the engine send what was heard.
            guard !heardSomething else { return stop() }
            fail(errorCode == Self.noSpeechErrorCode ? .noSpeech : .other, run: run)
        } else if isFinal {
            stop()
        }
    }

    private func observeInterruptions(run: Int) {
        interruptionObserver = NotificationCenter.default.addObserver(
            of: AVAudioSession.sharedInstance(),
            for: .didBecomeInactive
        ) { [weak self] message in
            // Deactivation by this app is its own doing. Only the system taking the session
            // away, for a call for example, is an interruption.
            if case .systemInterruption = message.deactivationResult {
                self?.fail(.interrupted, run: run)
            }
        }
    }

    /// The speech framework's code for "no speech detected".
    private static let noSpeechErrorCode = 1110

    private static func speechIsAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// The request is fed from the audio thread, which is how the framework expects it.
    private struct RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
    }

    // The tap and the result handler run off the main actor. They are built in nonisolated
    // functions so the closures do not inherit this class's isolation.
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, feeding box: RequestBox) throws {
        // A tenth of a second of audio, the smallest size a tap supports.
        let frames = AVAudioFrameCount(format.sampleRate / 10)
        try node.installAudioTap(onBus: 0, bufferSize: frames, format: format) { buffer, _ in
            box.request.append(AVAudioPCMBuffer(copying: buffer))
        }
    }

    nonisolated private static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (_ text: String?, _ isFinal: Bool, _ errorCode: Int?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onResult(result?.bestTranscription.formattedString, result?.isFinal ?? false, (error as NSError?)?.code)
        }
    }
}

/// Reads answers aloud with the system's speech synthesizer.
@MainActor
final class SpokenAnswerOutput: NSObject, AssistantSpeechOutput, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let locale: Locale
    private var current: ObjectIdentifier?
    private var waiting: CheckedContinuation<Void, Never>?

    init(locale: Locale = .current) {
        self.locale = locale
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        stop()
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier(.bcp47))
        let identifier = ObjectIdentifier(utterance)
        current = identifier
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(identifier, stopping: true)
            }
        }
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stop() {
        if let current {
            finish(current, stopping: true)
        }
    }

    /// An utterance that was stopped still reports its end later. The identifier keeps that
    /// late report from ending the wait of the utterance that followed it.
    private func finish(_ identifier: ObjectIdentifier, stopping: Bool) {
        guard identifier == current else { return }
        current = nil
        if stopping {
            synthesizer.stopSpeaking(at: .immediate)
        }
        waiting?.resume()
        waiting = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.finish(identifier, stopping: false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.finish(identifier, stopping: false)
        }
    }
}

/// Stands in for the microphone and the speaker where neither should be used: previews and
/// UI tests.
@MainActor
final class SilentSpeech: AssistantSpeechInput, AssistantSpeechOutput {
    func transcripts() -> AsyncThrowingStream<AssistantTranscript, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AssistantFailure.speechUnavailable) }
    }

    func speak(_ text: String) async {}

    func stop() {}
}
