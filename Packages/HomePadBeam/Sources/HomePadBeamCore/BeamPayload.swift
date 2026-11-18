import Foundation
import HomePadCore

/// What kind of page a beam carries. Unknown kinds from a newer sender read as `website`.
public enum BeamKind: String, Codable, Sendable, CaseIterable {
    case website
    case recipe
    case music
    case video

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BeamKind(rawValue: raw) ?? .website
    }
}

/// One page sent to another device.
public struct BeamPayload: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let sender: PeerDevice
    public let sentAt: Date
    public let kind: BeamKind

    public init(id: UUID, url: URL, title: String?, sender: PeerDevice, sentAt: Date, kind: BeamKind = .website) {
        self.id = id
        self.url = url
        self.title = BeamText.sanitizedTitle(title)
        self.sender = sender
        self.sentAt = sentAt
        self.kind = kind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            url: try container.decode(URL.self, forKey: .url),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            sender: try container.decode(PeerDevice.self, forKey: .sender),
            sentAt: try container.decode(Date.self, forKey: .sentAt),
            kind: try container.decodeIfPresent(BeamKind.self, forKey: .kind) ?? .website
        )
    }

    /// The same beam attributed to the device the transport authenticated, with its name cleaned.
    public func attributed(to device: PeerDevice) -> BeamPayload {
        BeamPayload(id: id, url: url, title: title, sender: device, sentAt: sentAt, kind: kind)
    }
}

/// What happened to a beam on the receiving device.
public enum BeamOutcome: Equatable, Sendable {
    case opened
    case awaitingApproval
    case declined
    case rateLimited
    case rejected(BeamURLRejection)
    /// The receiver reported something this version does not know.
    case unknown
}

public struct BeamReceipt: Codable, Equatable, Sendable {
    public let beamID: UUID
    public let outcome: BeamOutcome

    public init(beamID: UUID, outcome: BeamOutcome) {
        self.beamID = beamID
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case beamID, status, reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beamID = try container.decode(UUID.self, forKey: .beamID)
        let status = try container.decode(String.self, forKey: .status)
        let reason = try container.decodeIfPresent(String.self, forKey: .reason)
        switch status {
        case "opened": outcome = .opened
        case "awaitingApproval": outcome = .awaitingApproval
        case "declined": outcome = .declined
        case "rateLimited": outcome = .rateLimited
        case "rejected": outcome = .rejected(reason.flatMap(BeamURLRejection.init(rawValue:)) ?? .malformed)
        default: outcome = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beamID, forKey: .beamID)
        switch outcome {
        case .opened: try container.encode("opened", forKey: .status)
        case .awaitingApproval: try container.encode("awaitingApproval", forKey: .status)
        case .declined: try container.encode("declined", forKey: .status)
        case .rateLimited: try container.encode("rateLimited", forKey: .status)
        case .unknown: try container.encode("unknown", forKey: .status)
        case .rejected(let reason):
            try container.encode("rejected", forKey: .status)
            try container.encode(reason.rawValue, forKey: .reason)
        }
    }
}

/// The message carried on `PeerChannelName.beam`. Exactly one of the two fields is set.
public struct BeamMessage: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public enum Content: Equatable, Sendable {
        case beam(BeamPayload)
        case receipt(BeamReceipt)
    }

    public let version: Int
    public let content: Content

    public init(_ content: Content) {
        self.version = Self.currentVersion
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case beam, receipt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported beam message version")
        }
        if let beam = try container.decodeIfPresent(BeamPayload.self, forKey: .beam) {
            content = .beam(beam)
        } else if let receipt = try container.decodeIfPresent(BeamReceipt.self, forKey: .receipt) {
            content = .receipt(receipt)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .beam, in: container, debugDescription: "beam message has no content")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        switch content {
        case .beam(let beam): try container.encode(beam, forKey: .beam)
        case .receipt(let receipt): try container.encode(receipt, forKey: .receipt)
        }
    }
}
