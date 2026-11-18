import Foundation

/// What participants of a browse-together session send each other.
public enum SharePlayMessage: Codable, Equatable, Sendable {
    public static let version = 1

    /// `sequence` orders navigations across participants. Higher wins.
    case navigate(urlText: String, title: String?, sequence: UInt64)
    /// How far down the page the sender is, from 0 to 1, for the page at `sequence`.
    case scroll(fraction: Double, sequence: UInt64)
    case close

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case type = "t"
        case url, title, sequence = "seq", fraction
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported SharePlay message version")
        }
        switch try container.decode(String.self, forKey: .type) {
        case "navigate":
            self = .navigate(
                urlText: try container.decode(String.self, forKey: .url),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                sequence: try container.decode(UInt64.self, forKey: .sequence)
            )
        case "scroll":
            self = .scroll(
                fraction: try container.decode(Double.self, forKey: .fraction),
                sequence: try container.decode(UInt64.self, forKey: .sequence)
            )
        case "close":
            self = .close
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown SharePlay message type")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        switch self {
        case .navigate(let urlText, let title, let sequence):
            try container.encode("navigate", forKey: .type)
            try container.encode(urlText, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encode(sequence, forKey: .sequence)
        case .scroll(let fraction, let sequence):
            try container.encode("scroll", forKey: .type)
            try container.encode(fraction, forKey: .fraction)
            try container.encode(sequence, forKey: .sequence)
        case .close:
            try container.encode("close", forKey: .type)
        }
    }
}

public enum SharedBrowsingAction: Equatable, Sendable {
    case load(ValidatedURL, title: String?)
    case scroll(fraction: Double)
    case close
}

/// Keeps every participant on the same page. Each navigation carries a sequence number; the
/// highest wins, and a tie goes to the participant whose ID sorts last, so all devices settle on
/// the same page without a coordinator.
public struct SharedBrowsingState: Sendable {
    public let policy: BeamURLPolicy
    public private(set) var current: ValidatedURL?
    public private(set) var currentTitle: String?
    public private(set) var sequence: UInt64 = 0
    private var writer = ""

    public init(policy: BeamURLPolicy = BeamURLPolicy()) {
        self.policy = policy
    }

    /// Records a page the local browser moved to. Returns the message to send, or `nil` when the
    /// page is the one everyone is already on, which is what stops a received navigation from
    /// being sent back out.
    public mutating func localNavigation(to urlText: String, title: String?, localParticipant: String) -> SharePlayMessage? {
        guard case .success(let url) = policy.validate(urlText), url != current else { return nil }
        sequence += 1
        writer = localParticipant
        current = url
        currentTitle = BeamText.sanitizedTitle(title)
        return .navigate(urlText: url.url.absoluteString, title: currentTitle, sequence: sequence)
    }

    public mutating func receive(_ message: SharePlayMessage, from participant: String) -> SharedBrowsingAction? {
        switch message {
        case .navigate(let urlText, let title, let incoming):
            guard incoming > sequence || (incoming == sequence && participant > writer),
                  case .success(let url) = policy.validate(urlText)
            else { return nil }
            sequence = incoming
            writer = participant
            guard url != current else { return nil }
            current = url
            currentTitle = BeamText.sanitizedTitle(title)
            return .load(url, title: currentTitle)
        case .scroll(let fraction, let incoming):
            guard incoming == sequence, current != nil, fraction.isFinite else { return nil }
            return .scroll(fraction: min(max(fraction, 0), 1))
        case .close:
            current = nil
            currentTitle = nil
            return .close
        }
    }

    /// What to send someone who joined after the session started.
    public var catchUpMessage: SharePlayMessage? {
        current.map { .navigate(urlText: $0.url.absoluteString, title: currentTitle, sequence: sequence) }
    }

    public func scrollMessage(fraction: Double) -> SharePlayMessage? {
        guard current != nil, fraction.isFinite else { return nil }
        return .scroll(fraction: min(max(fraction, 0), 1), sequence: sequence)
    }
}
