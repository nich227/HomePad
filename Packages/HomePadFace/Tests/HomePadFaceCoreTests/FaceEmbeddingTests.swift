import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct FaceEmbeddingTests {
    @Test func init_whenValuesValid_thenNormalizesToUnitLength() throws {
        let embedding = try FaceEmbedding(modelID: "m", values: [3, 4])
        #expect(embedding.dimension == 2)
        #expect(abs(embedding.values[0] - 0.6) < 1e-6)
        #expect(abs(embedding.values[1] - 0.8) < 1e-6)
    }

    @Test func init_whenValuesHuge_thenNormalizesWithoutOverflow() throws {
        let embedding = try FaceEmbedding(modelID: "m", values: [3e30, 4e30])
        #expect(abs(embedding.values[0] - 0.6) < 1e-6)
    }

    @Test func init_whenModelIDEmpty_thenThrowsEmptyModelID() {
        #expect(throws: FaceEmbeddingError.emptyModelID) { try FaceEmbedding(modelID: "", values: [1]) }
    }

    @Test func init_whenVectorEmpty_thenThrowsEmptyVector() {
        #expect(throws: FaceEmbeddingError.emptyVector) { try FaceEmbedding(modelID: "m", values: []) }
    }

    @Test(arguments: [Float.nan, Float.infinity, -Float.infinity])
    func init_whenValueNotFinite_thenThrowsNonFiniteValue(value: Float) {
        #expect(throws: FaceEmbeddingError.nonFiniteValue) { try FaceEmbedding(modelID: "m", values: [1, value]) }
    }

    @Test(arguments: [Float(0), Float(1e-20)])
    func init_whenVectorHasNoLength_thenThrowsZeroNorm(value: Float) {
        #expect(throws: FaceEmbeddingError.zeroNorm) { try FaceEmbedding(modelID: "m", values: [value, 0]) }
    }

    @Test func similarity_whenVectorsComparable_thenReturnsCosine() throws {
        let base = try vector(0)
        #expect(try #require(base.similarity(to: vector(0))) == 1)
        #expect(abs(try #require(base.similarity(to: vector(60))) - 0.5) < 1e-6)
        #expect(abs(try #require(base.similarity(to: vector(90)))) < 1e-6)
        #expect(try #require(base.similarity(to: vector(180))) == -1)
    }

    @Test func similarity_whenModelIDsDiffer_thenReturnsNil() throws {
        let first = try vector(0, model: "model.a")
        let second = try vector(0, model: "model.b")
        #expect(first.similarity(to: second) == nil)
        #expect(!first.isComparable(to: second))
    }

    @Test func similarity_whenDimensionsDiffer_thenReturnsNil() throws {
        let first = try vector(0, dimension: 4)
        let second = try vector(0, dimension: 8)
        #expect(first.similarity(to: second) == nil)
    }

    @Test func codable_whenRoundTripped_thenIsBitExact() throws {
        let embedding = try FaceEmbedding(modelID: "m", values: [0.1, -0.7, 0.33, 0.25])
        let decoded = try JSONDecoder().decode(FaceEmbedding.self, from: JSONEncoder().encode(embedding))
        #expect(decoded == embedding)
    }

    private func json(modelID: String, floats: [Float], extraBytes: Int = 0) -> Data {
        var bytes = Data()
        for value in floats {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
        bytes.append(contentsOf: [UInt8](repeating: 0, count: extraBytes))
        return Data(#"{"modelID":"\#(modelID)","values":"\#(bytes.base64EncodedString())"}"#.utf8)
    }

    @Test func decode_whenStoredVectorIsUnit_thenSucceeds() throws {
        let decoded = try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "m", floats: [0.6, 0.8]))
        #expect(decoded.values == [0.6, 0.8])
    }

    @Test func decode_whenStoredVectorIsNotUnit_thenThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "m", floats: [3, 4]))
        }
    }

    @Test func decode_whenByteCountIsNotWholeFloats_thenThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "m", floats: [0.6, 0.8], extraBytes: 1))
        }
    }

    @Test func decode_whenModelIDEmpty_thenThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "", floats: [0.6, 0.8]))
        }
    }

    @Test func decode_whenVectorEmptyOrNotFinite_thenThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "m", floats: []))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FaceEmbedding.self, from: json(modelID: "m", floats: [.nan, 1]))
        }
    }
}

@Suite struct HeadPoseTests {
    private let bucketing = HeadPoseBucketing()

    @Test func bucket_whenFacingCamera_thenCenter() {
        #expect(bucketing.bucket(for: .frontal) == .center)
        #expect(bucketing.bucket(for: pose(yaw: 8, pitch: -8, roll: 10)) == .center)
    }

    @Test func bucket_whenTurnedOrTilted_thenMatchesDirection() {
        #expect(bucketing.bucket(for: pose(yaw: 25)) == .left)
        #expect(bucketing.bucket(for: pose(yaw: -25)) == .right)
        #expect(bucketing.bucket(for: pose(pitch: 20)) == .up)
        #expect(bucketing.bucket(for: pose(pitch: -20)) == .down)
    }

    @Test func bucket_whenBetweenCenterAndTurn_thenNil() {
        #expect(bucketing.bucket(for: pose(yaw: 12.5)) == nil)
    }

    @Test func bucket_whenDiagonal_thenNil() {
        #expect(bucketing.bucket(for: pose(yaw: 15, pitch: 14)) == nil)
        #expect(bucketing.bucket(for: pose(yaw: 25, pitch: 25)) == nil)
    }

    @Test func bucket_whenTurnedTooFarOrRolled_thenNil() {
        #expect(bucketing.bucket(for: pose(yaw: 60)) == nil)
        #expect(bucketing.bucket(for: pose(pitch: 50)) == nil)
        #expect(bucketing.bucket(for: pose(roll: 40)) == nil)
    }

    @Test func bucket_whenAngleNotFinite_thenNil() {
        #expect(bucketing.bucket(for: HeadPose(yaw: .nan, pitch: 0, roll: 0)) == nil)
        #expect(bucketing.bucket(for: HeadPose(yaw: 0, pitch: .infinity, roll: 0)) == nil)
        #expect(bucketing.bucket(for: HeadPose(yaw: 0, pitch: 0, roll: .nan)) == nil)
    }
}

@Suite struct FaceTemplateTests {
    private let profileID = UUID()

    @Test func init_whenSamplesEmpty_thenThrowsNoSamples() {
        #expect(throws: FaceTemplateError.noSamples) {
            try FaceTemplate(profileID: profileID, samples: [], createdAt: Date())
        }
    }

    @Test func init_whenSamplesComeFromDifferentModels_thenThrowsMixedModels() throws {
        let samples = [
            FaceTemplate.Sample(bucket: .center, embedding: try vector(0, model: "model.a")),
            FaceTemplate.Sample(bucket: .left, embedding: try vector(0, model: "model.b")),
        ]
        #expect(throws: FaceTemplateError.mixedModels) {
            try FaceTemplate(profileID: profileID, samples: samples, createdAt: Date())
        }
    }

    @Test func init_whenSamplesValid_thenTakesModelFromSamples() throws {
        let made = try template(profileID, degrees: [0, 10])
        #expect(made.modelID == testModelID)
        #expect(made.version == FaceTemplate.currentVersion)
        #expect(made.sampleCount(in: .center) == 2)
        #expect(made.sampleCount(in: .left) == 0)
    }

    @Test func bestSimilarity_whenSeveralSamples_thenReturnsHighest() throws {
        let made = try template(profileID, degrees: [0, 50])
        let best = try #require(made.bestSimilarity(to: vector(60)))
        #expect(abs(best - Float(cos(radians(10)))) < 1e-5)
    }

    @Test func bestSimilarity_whenProbeFromAnotherModel_thenNil() throws {
        let made = try template(profileID, degrees: [0])
        #expect(made.bestSimilarity(to: try vector(0, model: "other.model")) == nil)
    }

    @Test func codable_whenRoundTripped_thenEqual() throws {
        let made = try template(profileID, degrees: [0, 30], bucket: .up)
        let decoded = try JSONDecoder().decode(FaceTemplate.self, from: JSONEncoder().encode(made))
        #expect(decoded == made)
    }

    private func object(_ made: FaceTemplate) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(made)) as? [String: Any])
    }

    @Test func decode_whenVersionUnknown_thenThrows() throws {
        var fields = try object(template(profileID, degrees: [0]))
        fields["version"] = 99
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FaceTemplate.self, from: data) }
    }

    @Test func decode_whenTemplateModelDiffersFromSamples_thenThrows() throws {
        var fields = try object(template(profileID, degrees: [0]))
        fields["modelID"] = "another.model"
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FaceTemplate.self, from: data) }
    }

    @Test func decode_whenSamplesEmpty_thenThrows() throws {
        var fields = try object(template(profileID, degrees: [0]))
        fields["samples"] = [Any]()
        let data = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(FaceTemplate.self, from: data) }
    }
}
