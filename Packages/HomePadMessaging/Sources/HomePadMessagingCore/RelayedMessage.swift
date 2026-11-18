import CryptoKit
import Foundation

public enum MessageDirection: String, Sendable {
    case incoming, outgoing
}

public enum RelayedMessageError: Error, Equatable, Sendable {
    case emptySender
    case emptyBody
}

/// A message a companion learned about from a Shortcuts automation, or a reply its owner sent.
/// The body is memory-only, which also keeps this type and anything that stores it from being
/// given a `Codable` conformance.
public struct RelayedMessage: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let conversationID: String
    public let senderName: String
    /// Phone number or email, when the automation passed one.
    public let handle: String?
    public let body: MemoryOnly<String>
    public let receivedAt: Date
    public let direction: MessageDirection

    /// Trims the input, rejects blanks, and shortens text to the projection limits. Pass
    /// `conversationID` to add a reply to an existing thread; otherwise it is derived from the sender.
    public init(
        id: UUID,
        senderName: String,
        handle: String? = nil,
        text: String,
        receivedAt: Date,
        direction: MessageDirection = .incoming,
        conversationID: String? = nil,
        limits: ProjectionLimits = .standard
    ) throws(RelayedMessageError) {
        let sender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHandle = handle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHandle = (trimmedHandle?.isEmpty ?? true) ? nil : trimmedHandle?.projectionTruncated(to: limits.maxIdentifierLength)
        guard !sender.isEmpty else { throw .emptySender }
        guard !body.isEmpty else { throw .emptyBody }
        self.id = id
        self.senderName = sender.projectionTruncated(to: limits.maxTitleLength)
        self.handle = cleanHandle
        self.body = MemoryOnly(body.projectionTruncated(to: limits.maxBodyLength))
        self.receivedAt = receivedAt
        self.direction = direction
        self.conversationID = conversationID ?? Self.conversationID(senderName: sender, handle: cleanHandle)
    }

    /// A stable, opaque id for the thread with one correspondent. It is a digest so that names
    /// and phone numbers do not travel inside template and action ids.
    public static func conversationID(senderName: String, handle: String?) -> String {
        let key: String
        if let handle {
            let compact = handle.lowercased().filter { !$0.isWhitespace && !"-().".contains($0) }
            key = "h:" + compact
        } else {
            key = "n:" + senderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
