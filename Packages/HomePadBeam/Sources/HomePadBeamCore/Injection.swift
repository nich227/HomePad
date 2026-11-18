import CryptoKit
import Foundation

/// Source of cryptographically secure random bytes. Tests inject a fixed sequence.
public protocol RandomSource: Sendable {
    func bytes(_ count: Int) -> Data
}

public struct SystemRandomSource: RandomSource {
    public init() {}

    public func bytes(_ count: Int) -> Data {
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }
}

extension UUID {
    /// The 16 raw bytes, in the order the string form prints them.
    var rawBytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init?(rawBytes: Data) {
        guard rawBytes.count == 16 else { return nil }
        var value = UUID().uuid
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: rawBytes) }
        self.init(uuid: value)
    }
}
