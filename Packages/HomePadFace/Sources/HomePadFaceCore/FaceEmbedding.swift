import Accelerate
import Foundation

public enum FaceEmbeddingError: Error, Equatable, Sendable {
    case emptyModelID
    case emptyVector
    case nonFiniteValue
    case zeroNorm
}

/// A unit-length face vector tagged with the model that produced it. Vectors from different
/// models live in unrelated spaces, so they never compare.
public struct FaceEmbedding: Equatable, Sendable {
    /// Below this magnitude a vector is numerical noise, not a direction.
    static let minimumMagnitude: Float = 1e-12
    /// Allowed deviation from unit length when reading a stored vector.
    static let storedNormTolerance: Float = 1e-3

    public let modelID: String
    public let values: [Float]

    /// Normalizes `values` to unit length.
    public init(modelID: String, values: [Float]) throws(FaceEmbeddingError) {
        guard !modelID.isEmpty else { throw .emptyModelID }
        guard !values.isEmpty else { throw .emptyVector }
        guard values.allSatisfy(\.isFinite) else { throw .nonFiniteValue }
        // Scaling by the peak first keeps the sum of squares from overflowing for large inputs.
        let peak = vDSP.maximumMagnitude(values)
        guard peak > Self.minimumMagnitude else { throw .zeroNorm }
        let scaled = vDSP.divide(values, peak)
        self.modelID = modelID
        self.values = vDSP.divide(scaled, vDSP.sumOfSquares(scaled).squareRoot())
    }

    public var dimension: Int { values.count }

    public func isComparable(to other: FaceEmbedding) -> Bool {
        modelID == other.modelID && values.count == other.values.count
    }

    /// Cosine similarity in -1...1, or `nil` when the two vectors come from different models or
    /// have different dimensions.
    public func similarity(to other: FaceEmbedding) -> Float? {
        guard isComparable(to: other) else { return nil }
        return min(1, max(-1, vDSP.dot(values, other.values)))
    }
}

extension FaceEmbedding: Codable {
    private enum CodingKeys: String, CodingKey {
        case modelID
        case values
    }

    /// Stored vectors must already be unit length. They are not renormalized, so a round trip is
    /// bit exact and a damaged item is rejected instead of repaired.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modelID = try container.decode(String.self, forKey: .modelID)
        let bytes = try container.decode(Data.self, forKey: .values)
        let width = MemoryLayout<UInt32>.size
        let values: [Float] = bytes.withUnsafeBytes { raw in
            (0..<raw.count / width).map { index in
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: index * width, as: UInt32.self)))
            }
        }
        guard
            bytes.count % width == 0,
            !modelID.isEmpty,
            !values.isEmpty,
            values.allSatisfy(\.isFinite),
            abs(vDSP.sumOfSquares(values).squareRoot() - 1) <= Self.storedNormTolerance
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .values,
                in: container,
                debugDescription: "Stored face embedding is not a unit vector."
            )
        }
        self.modelID = modelID
        self.values = values
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelID, forKey: .modelID)
        var bytes = Data(capacity: values.count * MemoryLayout<UInt32>.size)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
        try container.encode(bytes, forKey: .values)
    }
}
