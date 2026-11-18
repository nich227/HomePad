import Foundation
import HomePadCore
@testable import HomePadFaceCore

let testModelID = "test.model.4"

/// A unit vector at `degrees` in the plane of the first two axes. The cosine similarity of two
/// such vectors is the cosine of the angle between them.
func vector(_ degrees: Double, model: String = testModelID, dimension: Int = 4) throws -> FaceEmbedding {
    var values = [Float](repeating: 0, count: dimension)
    values[0] = Float(cos(degrees * .pi / 180))
    values[1] = Float(sin(degrees * .pi / 180))
    return try FaceEmbedding(modelID: model, values: values)
}

func template(
    _ profileID: UUID,
    degrees: [Double],
    model: String = testModelID,
    bucket: HeadPoseBucket = .center
) throws -> FaceTemplate {
    try FaceTemplate(
        profileID: profileID,
        samples: degrees.map { FaceTemplate.Sample(bucket: bucket, embedding: try vector($0, model: model)) },
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
}

func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

func pose(yaw: Double = 0, pitch: Double = 0, roll: Double = 0) -> HeadPose {
    HeadPose(yaw: radians(yaw), pitch: radians(pitch), roll: radians(roll))
}

/// A grid of depth readings over the unit square, with depth given by `surface(x, y)`.
func depthGrid(side: Int = 12, _ surface: (Float, Float) -> Float) -> [DepthPoint] {
    (0..<side).flatMap { row in
        (0..<side).map { column in
            let x = (Float(column) + 0.5) / Float(side)
            let y = (Float(row) + 0.5) / Float(side)
            return DepthPoint(x: x, y: y, depth: surface(x, y))
        }
    }
}

/// A cone with its tip (the nose) 3 cm closer to the camera than its rim.
func faceLikeDepth(distance: Float = 0.5) -> FaceDepthStatistics {
    FaceDepthStatistics(points: depthGrid { x, y in
        let radius = ((x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5)).squareRoot()
        return distance - 0.03 * max(0, 1 - radius / 0.5)
    })
}

/// A flat surface, tilted so its depth range is large while it stays a plane.
func flatDepth(distance: Float = 0.5) -> FaceDepthStatistics {
    FaceDepthStatistics(points: depthGrid { x, y in distance + 0.08 * (x - 0.5) + 0.02 * (y - 0.5) })
}

func frame(
    at timestamp: TimeInterval,
    degrees: Double?,
    model: String = testModelID,
    size: Double = 0.3,
    pose: HeadPose = .frontal,
    quality: Float = 0.6,
    depth: FaceDepthStatistics? = nil,
    eyeOpenness: Float? = nil,
    faces: Int = 1,
    position: FaceViewerPosition? = nil,
    distance: Double? = 0.6,
    light: SceneLightSample? = nil
) throws -> FaceFrameObservation {
    FaceFrameObservation(
        timestamp: timestamp,
        prominentFaceCount: faces,
        primary: FaceObservationSample(
            sizeFraction: size,
            pose: pose,
            captureQuality: quality,
            embedding: try degrees.map { try vector($0, model: model) },
            depth: depth,
            eyeOpenness: eyeOpenness,
            viewerPosition: position,
            distance: distance.map { FaceDistanceEstimate(meters: $0, source: .faceSize) }
        ),
        light: light
    )
}
