import Foundation
import HomePadCore

/// How far away a face is, and how that was measured.
public struct FaceDistanceEstimate: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        /// Measured by the depth camera.
        case depth
        /// Worked out from the size of the face in the frame. Rough.
        case faceSize
    }

    public let meters: Double
    public let source: Source

    public init(meters: Double, source: Source) {
        self.meters = meters
        self.source = source
    }
}

/// Turns what one frame knows about a face into a distance in meters.
public struct FaceDistanceModel: Equatable, Sendable {
    /// Height of the face box a detector draws on an adult, in meters. Real faces differ by a
    /// quarter either way (children, head pose, where the detector puts the box), and the
    /// distance worked out from face size is off by the same share.
    public var typicalFaceHeight: Double
    /// Distances the depth camera can be trusted for, in meters.
    public var depthRange: ClosedRange<Double>
    public var minimumDepthSamples: Int
    public var minimumDepthValidFraction: Float
    /// A depth reading this many times larger or smaller than the face-size estimate is a
    /// reading of something else, such as the wall behind a small face box.
    public var maximumDepthDisagreement: Double

    public init(
        typicalFaceHeight: Double = 0.17,
        depthRange: ClosedRange<Double> = 0.15...3,
        minimumDepthSamples: Int = 20,
        minimumDepthValidFraction: Float = 0.3,
        maximumDepthDisagreement: Double = 2.5
    ) {
        self.typicalFaceHeight = typicalFaceHeight
        self.depthRange = depthRange
        self.minimumDepthSamples = minimumDepthSamples
        self.minimumDepthValidFraction = minimumDepthValidFraction
        self.maximumDepthDisagreement = maximumDepthDisagreement
    }

    /// Distance from the size of the face in the frame, by the pinhole camera relation: an
    /// object of known height that covers fewer pixels is farther away.
    ///
    /// - Parameters:
    ///   - normalizedFaceHeight: height of the face box over the height of the upright frame.
    ///   - frameWidth: width of the upright frame in pixels.
    ///   - frameHeight: height of the upright frame in pixels.
    ///   - fieldOfViewDegrees: the camera format's field of view, which spans the frame's longer
    ///     side. Read it from the active format. It differs between devices and formats.
    /// - Returns: `nil` when an input is missing or not usable.
    public func metersFromFaceSize(
        normalizedFaceHeight: Double,
        frameWidth: Double,
        frameHeight: Double,
        fieldOfViewDegrees: Double
    ) -> Double? {
        let longerSide = max(frameWidth, frameHeight)
        let facePixels = normalizedFaceHeight * frameHeight
        guard
            facePixels.isFinite, facePixels > 0,
            longerSide.isFinite, min(frameWidth, frameHeight) > 0,
            fieldOfViewDegrees > 1, fieldOfViewDegrees < 179
        else { return nil }
        let focalLengthPixels = longerSide / (2 * tan(fieldOfViewDegrees * .pi / 360))
        return focalLengthPixels * typicalFaceHeight / facePixels
    }

    /// Prefers the depth camera's reading, which is a real distance: the median of the valid
    /// readings on the face. Falls back to the face-size estimate when depth is missing, sparse,
    /// out of the sensor's range, or far off from what the face size says.
    public func estimate(depth: FaceDepthStatistics?, faceSizeMeters: Double?) -> FaceDistanceEstimate? {
        let fromSize = faceSizeMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        if let depth, isPlausible(depth, comparedWith: fromSize) {
            return FaceDistanceEstimate(meters: Double(depth.medianDepth), source: .depth)
        }
        return fromSize.map { FaceDistanceEstimate(meters: $0, source: .faceSize) }
    }

    private func isPlausible(_ depth: FaceDepthStatistics, comparedWith fromSize: Double?) -> Bool {
        let meters = Double(depth.medianDepth)
        guard
            depth.validCount >= minimumDepthSamples,
            depth.validFraction >= minimumDepthValidFraction,
            depthRange.contains(meters)
        else { return false }
        guard let fromSize else { return true }
        return meters <= fromSize * maximumDepthDisagreement && meters >= fromSize / maximumDepthDisagreement
    }
}

/// Where the three zones begin, in meters. Nearer than `nearBoundary` is near (arm's reach),
/// farther than `farBoundary` is far, and in between is mid.
public struct ProximityPolicy: Equatable, Sendable {
    public let nearBoundary: Double
    public let farBoundary: Double
    /// Share of a boundary the distance must pass beyond it before the zone changes, so a person
    /// standing at a boundary does not flip the layout back and forth.
    public let hysteresis: Double
    /// Weight of each new distance sample, in 0...1. Lower is steadier and slower to follow.
    public let responsiveness: Double

    public init(nearBoundary: Double = 1, farBoundary: Double = 2.5, hysteresis: Double = 0.1, responsiveness: Double = 0.5) {
        let near = max(0.05, nearBoundary)
        let far = max(near, farBoundary)
        self.nearBoundary = near
        self.farBoundary = far
        // Past this share the two bands would overlap and the mid zone could not be reached.
        self.hysteresis = min(max(0, hysteresis), (far - near) / (far + near))
        self.responsiveness = min(1, max(0.05, responsiveness))
    }

    /// Both boundaries multiplied by `factor`.
    public func scaled(by factor: Double) -> ProximityPolicy {
        ProximityPolicy(
            nearBoundary: nearBoundary * factor,
            farBoundary: farBoundary * factor,
            hysteresis: hysteresis,
            responsiveness: responsiveness
        )
    }

    /// Near within 1 m, far beyond 2.5 m.
    public static let standard = ProximityPolicy()
    /// The person must come closer for each step up in detail.
    public static let closer = standard.scaled(by: 0.75)
    /// Each step up in detail starts from farther away.
    public static let farther = standard.scaled(by: 1.3)
}

/// Turns a stream of distance estimates into a steady zone.
public struct ProximityEstimator: Equatable, Sendable {
    public let policy: ProximityPolicy
    public private(set) var proximity: Proximity = .far
    /// The smoothed distance in meters, or `nil` before the first usable estimate.
    public private(set) var distance: Double?

    public init(policy: ProximityPolicy = .standard) {
        self.policy = policy
    }

    /// Face box height over the frame's shorter side, from a box normalized to the frame.
    public static func sizeFraction(normalizedHeight: Double, frameWidth: Double, frameHeight: Double) -> Double {
        let shorter = min(frameWidth, frameHeight)
        guard shorter > 0, normalizedHeight.isFinite else { return 0 }
        return max(0, normalizedHeight * frameHeight / shorter)
    }

    /// Feeds one frame's distance. A frame without a usable distance keeps the current zone.
    @discardableResult
    public mutating func update(distance sample: Double?) -> Proximity {
        guard let sample, sample.isFinite, sample > 0 else { return proximity }
        guard let previous = distance else {
            // Nothing to hold on to yet, so the first estimate picks its zone outright.
            distance = sample
            proximity = sample < policy.nearBoundary ? .near : (sample > policy.farBoundary ? .far : .mid)
            return proximity
        }
        let smoothed = previous + policy.responsiveness * (sample - previous)
        distance = smoothed
        let nearIn = policy.nearBoundary * (1 - policy.hysteresis)
        let nearOut = policy.nearBoundary * (1 + policy.hysteresis)
        let farIn = policy.farBoundary * (1 - policy.hysteresis)
        let farOut = policy.farBoundary * (1 + policy.hysteresis)
        switch proximity {
        case .near:
            if smoothed > farOut { proximity = .far } else if smoothed > nearOut { proximity = .mid }
        case .mid:
            if smoothed < nearIn { proximity = .near } else if smoothed > farOut { proximity = .far }
        case .far:
            if smoothed < nearIn { proximity = .near } else if smoothed < farIn { proximity = .mid }
        }
        return proximity
    }

    public mutating func reset() {
        proximity = .far
        distance = nil
    }
}
