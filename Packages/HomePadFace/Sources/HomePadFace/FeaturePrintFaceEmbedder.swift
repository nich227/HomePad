import CoreVideo
import Foundation
import HomePadFaceCore
import Vision

/// Development fallback that describes the face crop with Vision's generic image feature print.
///
/// A feature print is trained to tell images apart, not people. Two different people in the
/// same pose and light can score closer than one person in two poses. It exists so the app runs
/// end to end without a bundled model. Do not ship it as the recognizer.
public struct FeaturePrintFaceEmbedder: FaceEmbedder {
    public let modelID: String
    public let displayName = "Vision feature print (development only)"
    public let inputSide = 224
    /// Stricter than a face model's policy and still uncalibrated.
    public let matchPolicy = MatchPolicy.featurePrintDevelopment
    public let isDevelopmentFallback = true

    public init() {
        modelID = "vision.featureprint.r\(VNGenerateImageFeaturePrintRequest.currentRevision)"
    }

    public func embedding(forAlignedFace crop: CVPixelBuffer) throws(FaceEmbedderError) -> FaceEmbedding {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: crop, orientation: .up)
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else {
            throw .predictionFailed
        }
        let values: [Float]
        switch observation.elementType {
        case .float:
            values = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(observation.elementCount)) }
        case .double:
            values = observation.data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(observation.elementCount).map(Float.init) }
        default:
            throw .predictionFailed
        }
        do {
            return try FaceEmbedding(modelID: modelID, values: values)
        } catch {
            throw .invalidOutput(error)
        }
    }
}
