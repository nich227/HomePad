import Foundation

/// Everything the recognition logic needs to know about the primary face in one frame. It holds
/// no pixels.
public struct FaceObservationSample: Equatable, Sendable {
    /// Face box height over the frame's shorter side.
    public let sizeFraction: Double
    public let pose: HeadPose
    /// Capture quality in 0...1.
    public let captureQuality: Float
    /// `nil` when no embedding could be computed for this frame.
    public let embedding: FaceEmbedding?
    /// `nil` when the camera delivered no depth for this frame.
    public let depth: FaceDepthStatistics?
    public let eyeOpenness: Float?
    /// Center of the face in the mirror view.
    public let viewerPosition: FaceViewerPosition?
    /// How far away the face is, when it could be estimated.
    public let distance: FaceDistanceEstimate?

    public init(
        sizeFraction: Double,
        pose: HeadPose,
        captureQuality: Float,
        embedding: FaceEmbedding?,
        depth: FaceDepthStatistics? = nil,
        eyeOpenness: Float? = nil,
        viewerPosition: FaceViewerPosition? = nil,
        distance: FaceDistanceEstimate? = nil
    ) {
        self.viewerPosition = viewerPosition
        self.distance = distance
        self.sizeFraction = sizeFraction
        self.pose = pose
        self.captureQuality = captureQuality
        self.embedding = embedding
        self.depth = depth
        self.eyeOpenness = eyeOpenness
    }
}

public struct FaceFrameObservation: Equatable, Sendable {
    /// Seconds on a monotonic clock.
    public let timestamp: TimeInterval
    /// Faces of comparable size in the frame, the primary one included.
    public let prominentFaceCount: Int
    public let primary: FaceObservationSample?
    /// What the frame says about the light in the room, with or without a face in it.
    public let light: SceneLightSample?

    public init(
        timestamp: TimeInterval,
        prominentFaceCount: Int,
        primary: FaceObservationSample?,
        light: SceneLightSample? = nil
    ) {
        self.timestamp = timestamp
        self.prominentFaceCount = prominentFaceCount
        self.primary = primary
        self.light = light
    }

    public static func empty(at timestamp: TimeInterval, light: SceneLightSample? = nil) -> FaceFrameObservation {
        FaceFrameObservation(timestamp: timestamp, prominentFaceCount: 0, primary: nil, light: light)
    }
}

/// Lets through at most one frame per interval. Timestamps are seconds on a monotonic clock.
public struct FrameThrottle: Equatable, Sendable {
    public private(set) var minimumInterval: TimeInterval
    private var lastAccepted: TimeInterval?

    public init(framesPerSecond: Double) {
        self.minimumInterval = Self.interval(for: framesPerSecond)
    }

    public mutating func setRate(framesPerSecond: Double) {
        minimumInterval = Self.interval(for: framesPerSecond)
    }

    public mutating func shouldProcess(at timestamp: TimeInterval) -> Bool {
        // A timestamp that went backward means the clock restarted, so the frame is let through.
        if let lastAccepted, timestamp >= lastAccepted, timestamp - lastAccepted < minimumInterval {
            return false
        }
        lastAccepted = timestamp
        return true
    }

    private static func interval(for framesPerSecond: Double) -> TimeInterval {
        framesPerSecond > 0 ? 1 / framesPerSecond : 0
    }
}
