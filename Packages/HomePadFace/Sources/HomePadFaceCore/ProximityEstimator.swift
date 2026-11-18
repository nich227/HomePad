import Foundation
import HomePadCore

/// Face size bounds for near and far. The size is the face box height as a fraction of the
/// frame's shorter side. `nearExit` is lower than `nearEnter` so a person standing at the
/// boundary does not flip the layout back and forth. The useful values depend on the camera's
/// field of view, so calibrate per device.
public struct ProximityPolicy: Equatable, Sendable {
    public let nearEnter: Double
    public let nearExit: Double

    public init(nearEnter: Double, nearExit: Double) {
        self.nearEnter = nearEnter
        self.nearExit = min(nearExit, nearEnter)
    }

    public static let standard = ProximityPolicy(nearEnter: 0.22, nearExit: 0.16)
    /// The person must come closer before the hub switches to the near layout.
    public static let closer = ProximityPolicy(nearEnter: 0.3, nearExit: 0.22)
    /// The hub switches to the near layout from farther away.
    public static let farther = ProximityPolicy(nearEnter: 0.15, nearExit: 0.11)
}

public struct ProximityEstimator: Equatable, Sendable {
    public let policy: ProximityPolicy
    public private(set) var proximity: Proximity = .far

    public init(policy: ProximityPolicy = .standard) {
        self.policy = policy
    }

    /// Face box height over the frame's shorter side, from a box normalized to the frame.
    public static func sizeFraction(normalizedHeight: Double, frameWidth: Double, frameHeight: Double) -> Double {
        let shorter = min(frameWidth, frameHeight)
        guard shorter > 0, normalizedHeight.isFinite else { return 0 }
        return max(0, normalizedHeight * frameHeight / shorter)
    }

    @discardableResult
    public mutating func update(sizeFraction: Double) -> Proximity {
        switch proximity {
        case .far where sizeFraction >= policy.nearEnter: proximity = .near
        case .near where sizeFraction < policy.nearExit: proximity = .far
        default: break
        }
        return proximity
    }

    public mutating func reset() {
        proximity = .far
    }
}
