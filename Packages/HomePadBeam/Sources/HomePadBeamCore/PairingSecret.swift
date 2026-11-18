import Foundation

public enum PairingSecretError: Error, Equatable, Sendable {
    case wrongLength(Int)
}

/// The 32 random bytes shared between a hub and one companion at pairing time. Its text and
/// mirror forms are redacted so it cannot reach a log through string interpolation or `dump`.
public struct PairingSecret: Equatable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let byteCount = 32

    public let bytes: Data

    public init(bytes: Data) throws(PairingSecretError) {
        guard bytes.count == Self.byteCount else { throw .wrongLength(bytes.count) }
        self.bytes = Data(bytes)
    }

    /// Throws when the random source does not return exactly `byteCount` bytes.
    public static func generate(using random: any RandomSource) throws(PairingSecretError) -> PairingSecret {
        try PairingSecret(bytes: random.bytes(byteCount))
    }

    public init(from decoder: any Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        do {
            try self.init(bytes: data)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "pairing secret has the wrong length"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }

    public var description: String { "PairingSecret(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
