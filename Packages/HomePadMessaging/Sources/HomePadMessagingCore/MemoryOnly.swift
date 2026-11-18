import Foundation

/// Wraps content that may live in memory but must never be written to disk, a log, or a crash
/// report: projected screens and anything else that belongs to one household member.
///
/// The wrapper has no `Codable` conformance and declares that it never will, so a type that stores
/// one cannot be given a synthesized `Codable` conformance and saved. Printing, string
/// interpolation, `dump`, and `Mirror` all show a placeholder instead of the content.
public struct MemoryOnly<Value: Sendable>: Sendable {
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    /// The only way to read the content. Search for `reveal()` to audit every place it is used.
    public func reveal() -> Value {
        value
    }

    public mutating func mutate<Failure: Error>(_ body: (inout Value) throws(Failure) -> Void) throws(Failure) {
        try body(&value)
    }
}

extension MemoryOnly: Equatable where Value: Equatable {}

extension MemoryOnly: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static var placeholder: String { "<memory-only>" }

    public var description: String { Self.placeholder }
    public var debugDescription: String { Self.placeholder }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

@available(*, unavailable, message: "Memory-only content must not be encoded or persisted.")
extension MemoryOnly: Encodable {
    public func encode(to encoder: any Encoder) throws {}
}

@available(*, unavailable, message: "Memory-only content must not be decoded from storage.")
extension MemoryOnly: Decodable {
    public init(from decoder: any Decoder) throws { throw CancellationError() }
}
