import Foundation

/// Why a request ended without an answer.
public enum AssistantFailure: Error, Equatable, Sendable {
    case noSpeech
    /// This device cannot recognize speech without a server, or not in this language.
    case speechUnavailable
    case speechNotPermitted
    case microphoneNotPermitted
    /// Something else took the microphone, such as a call.
    case interrupted
    case modelUnavailable
    case contextTooLong
    /// The model or its guardrails declined to answer.
    case refused
    case unsupportedLanguage
    case busy
    case timedOut
    case unknown

    /// Errors from the Assistant's own parts pass through. Anything else is unknown.
    public init(_ error: any Error) {
        self = (error as? AssistantFailure) ?? .unknown
    }

    public init(_ kind: ModelErrorKind) {
        self = switch kind {
        case .contextSizeExceeded: .contextTooLong
        case .guardrailViolation, .refusal: .refused
        case .rateLimited, .concurrentRequests: .busy
        case .assetsUnavailable: .modelUnavailable
        case .unsupportedLanguage: .unsupportedLanguage
        case .timeout: .timedOut
        case .other: .unknown
        }
    }

    public init(_ kind: SpeechErrorKind) {
        self = switch kind {
        case .recognizerUnavailable, .onDeviceUnsupported: .speechUnavailable
        case .speechDenied: .speechNotPermitted
        case .microphoneDenied: .microphoneNotPermitted
        case .interrupted: .interrupted
        case .noSpeech: .noSpeech
        case .other: .unknown
        }
    }
}

/// The language model's errors, restated without the framework's types.
public enum ModelErrorKind: Equatable, Sendable, CaseIterable {
    case contextSizeExceeded
    case guardrailViolation
    case refusal
    case rateLimited
    case concurrentRequests
    case assetsUnavailable
    case unsupportedLanguage
    case timeout
    case other
}

/// What can go wrong while listening, restated without the framework's types.
public enum SpeechErrorKind: Equatable, Sendable, CaseIterable {
    case recognizerUnavailable
    case onDeviceUnsupported
    case speechDenied
    case microphoneDenied
    case interrupted
    case noSpeech
    case other
}
