import Foundation

/// Head orientation in radians, from the person's own point of view: positive yaw is a turn to
/// their left, positive pitch is looking up. The camera layer converts to this convention.
public struct HeadPose: Equatable, Sendable {
    public let yaw: Double
    public let pitch: Double
    public let roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let frontal = HeadPose(yaw: 0, pitch: 0, roll: 0)
}

public enum HeadPoseBucket: String, CaseIterable, Codable, Sendable {
    case center, left, right, up, down
}

/// Maps a head pose to an enrollment bucket. Poses between two buckets, diagonal poses, and
/// poses turned too far for a usable embedding map to no bucket.
public struct HeadPoseBucketing: Equatable, Sendable {
    public var centerLimit: Double
    public var turnMinimum: Double
    public var turnMaximum: Double
    public var tiltMinimum: Double
    public var tiltMaximum: Double
    /// How far the other axis may stray while turning or tilting.
    public var offAxisLimit: Double
    public var rollLimit: Double

    public init(
        centerLimit: Double = 10 * .pi / 180,
        turnMinimum: Double = 15 * .pi / 180,
        turnMaximum: Double = 40 * .pi / 180,
        tiltMinimum: Double = 12 * .pi / 180,
        tiltMaximum: Double = 35 * .pi / 180,
        offAxisLimit: Double = 15 * .pi / 180,
        rollLimit: Double = 25 * .pi / 180
    ) {
        self.centerLimit = centerLimit
        self.turnMinimum = turnMinimum
        self.turnMaximum = turnMaximum
        self.tiltMinimum = tiltMinimum
        self.tiltMaximum = tiltMaximum
        self.offAxisLimit = offAxisLimit
        self.rollLimit = rollLimit
    }

    public func bucket(for pose: HeadPose) -> HeadPoseBucket? {
        let yaw = abs(pose.yaw)
        let pitch = abs(pose.pitch)
        guard yaw.isFinite, pitch.isFinite, abs(pose.roll) <= rollLimit else { return nil }
        if yaw <= centerLimit, pitch <= centerLimit { return .center }
        let turned = (turnMinimum...turnMaximum).contains(yaw) && pitch <= offAxisLimit
        let tilted = (tiltMinimum...tiltMaximum).contains(pitch) && yaw <= offAxisLimit
        switch (turned, tilted) {
        case (true, false): return pose.yaw > 0 ? .left : .right
        case (false, true): return pose.pitch > 0 ? .up : .down
        default: return nil
        }
    }
}
