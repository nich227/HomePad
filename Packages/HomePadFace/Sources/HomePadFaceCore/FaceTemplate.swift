import Foundation

public enum FaceTemplateError: Error, Equatable, Sendable {
    case noSamples
    case mixedModels
}

/// One household member's enrolled face: embeddings from one model, tagged by head pose.
public struct FaceTemplate: Equatable, Sendable {
    public struct Sample: Equatable, Codable, Sendable {
        public let bucket: HeadPoseBucket
        public let embedding: FaceEmbedding

        public init(bucket: HeadPoseBucket, embedding: FaceEmbedding) {
            self.bucket = bucket
            self.embedding = embedding
        }
    }

    public static let currentVersion = 1

    public let version: Int
    public let profileID: UUID
    public let modelID: String
    public let createdAt: Date
    public let samples: [Sample]

    public init(profileID: UUID, samples: [Sample], createdAt: Date) throws(FaceTemplateError) {
        guard let first = samples.first else { throw .noSamples }
        guard samples.allSatisfy({ $0.embedding.isComparable(to: first.embedding) }) else { throw .mixedModels }
        self.version = Self.currentVersion
        self.profileID = profileID
        self.modelID = first.embedding.modelID
        self.createdAt = createdAt
        self.samples = samples
    }

    /// Highest similarity between the probe and any sample, or `nil` when the probe comes from a
    /// different model than this template.
    public func bestSimilarity(to probe: FaceEmbedding) -> Float? {
        samples.compactMap { $0.embedding.similarity(to: probe) }.max()
    }

    public func sampleCount(in bucket: HeadPoseBucket) -> Int {
        samples.count { $0.bucket == bucket }
    }
}

extension FaceTemplate: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, profileID, modelID, createdAt, samples
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported face template version."
            )
        }
        let modelID = try container.decode(String.self, forKey: .modelID)
        let samples = try container.decode([Sample].self, forKey: .samples)
        guard
            let first = samples.first,
            first.embedding.modelID == modelID,
            samples.allSatisfy({ $0.embedding.isComparable(to: first.embedding) })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .samples,
                in: container,
                debugDescription: "Face template samples do not match the template model."
            )
        }
        self.version = version
        self.profileID = try container.decode(UUID.self, forKey: .profileID)
        self.modelID = modelID
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.samples = samples
    }
}
