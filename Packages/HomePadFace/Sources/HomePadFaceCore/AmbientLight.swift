import Foundation

/// The exposure the capture device is using for the current frame. The camera raises its
/// sensitivity and exposure time as a room gets darker, so these say more about the room than
/// the brightness of the pixels does.
public struct CameraExposure: Equatable, Sendable {
    public let iso: Double
    /// Seconds.
    public let exposureDuration: Double
    /// The lens f-number.
    public let aperture: Double
    /// How far the metered scene is from the exposure the camera aims for, in stops. Negative
    /// when the scene is darker than the camera can compensate for.
    public let targetOffset: Double

    public init(iso: Double, exposureDuration: Double, aperture: Double, targetOffset: Double) {
        self.iso = iso
        self.exposureDuration = exposureDuration
        self.aperture = aperture
        self.targetOffset = targetOffset
    }

    /// The scene's exposure value at ISO 100, from the photographic exposure equation, corrected
    /// by the target offset so it keeps falling after the camera runs out of range. About 6 in a
    /// lit living room and below 1 in a dark one. `nil` when the device reported nothing usable.
    public var sceneExposureValue: Double? {
        guard
            iso.isFinite, iso > 0,
            exposureDuration.isFinite, exposureDuration > 0,
            aperture.isFinite, aperture > 0,
            targetOffset.isFinite
        else { return nil }
        return log2(aperture * aperture / exposureDuration) - log2(iso / 100) + targetOffset
    }
}

/// What one analyzed frame knows about the light in the room. It holds no pixels.
public struct SceneLightSample: Equatable, Sendable {
    public let exposure: CameraExposure?
    /// Mean of a sparse sample of the frame's luma, in 0...1.
    public let meanLuma: Double?

    public init(exposure: CameraExposure?, meanLuma: Double?) {
        self.exposure = exposure
        self.meanLuma = meanLuma
    }
}

public enum SceneBrightness {
    /// Exposure values mapped to brightness 0 and 1. The low end is a room lit by a faint night
    /// light, the high end is daylight indoors next to a window.
    public static let exposureValueRange: ClosedRange<Double> = -2...10

    /// Brightness in 0...1 for a scene exposure value.
    public static func level(exposureValue: Double) -> Double {
        let span = exposureValueRange.upperBound - exposureValueRange.lowerBound
        return min(1, max(0, (exposureValue - exposureValueRange.lowerBound) / span))
    }

    /// Rough illuminance for a scene exposure value, for documentation and calibration.
    public static func approximateLux(exposureValue: Double) -> Double {
        2.5 * pow(2, exposureValue)
    }

    /// Brightness in 0...1 for one frame. Uses the device's exposure when it is there. Without
    /// it, falls back to the pixel brightness, which the camera's auto exposure flattens, so it
    /// only separates "dark beyond what the camera can lift" from everything else.
    public static func level(for sample: SceneLightSample) -> Double? {
        if let exposureValue = sample.exposure?.sceneExposureValue {
            return level(exposureValue: exposureValue)
        }
        guard let luma = sample.meanLuma, luma.isFinite else { return nil }
        return min(1, max(0, luma))
    }

    /// Mean luma in 0...1 from a sum of 8-bit luma samples. Video-range luma runs from 16 to 235.
    public static func meanLuma(sum: Int, count: Int, isVideoRange: Bool) -> Double? {
        guard count > 0, sum >= 0 else { return nil }
        let mean = Double(sum) / Double(count)
        let scaled = isVideoRange ? (mean - 16) / 219 : mean / 255
        return min(1, max(0, scaled))
    }
}

public struct AmbientLightPolicy: Equatable, Sendable {
    /// Seconds over which the brightness is averaged.
    public var smoothingTime: TimeInterval
    /// Seconds to wait after the camera starts before trusting it. Auto exposure is still
    /// settling then.
    public var settlingTime: TimeInterval
    /// At or below this brightness the room counts as dark. About 4 lux with the default range.
    public var darkEnter: Double
    /// At or above this brightness the room counts as lit again. About 8 lux with the default
    /// range. Higher than `darkEnter` so a room at the boundary does not flip back and forth.
    public var darkExit: Double
    /// Seconds the brightness must stay past a bound before the decision changes, so a passing
    /// shadow or a light switched on for a moment does not flip it.
    public var minimumDwell: TimeInterval
    /// The reported brightness moves in steps of at least this size.
    public var reportingStep: Double

    public init(
        smoothingTime: TimeInterval = 2,
        settlingTime: TimeInterval = 1.5,
        darkEnter: Double = 0.22,
        darkExit: Double = 0.3,
        minimumDwell: TimeInterval = 8,
        reportingStep: Double = 0.02
    ) {
        self.smoothingTime = max(0, smoothingTime)
        self.settlingTime = max(0, settlingTime)
        self.darkEnter = darkEnter
        self.darkExit = max(darkEnter, darkExit)
        self.minimumDwell = max(0, minimumDwell)
        self.reportingStep = max(0, reportingStep)
    }
}

/// Smooths the per-frame brightness and decides whether the room is dark. Timestamps are
/// seconds on a monotonic clock.
public struct AmbientLightEstimator: Equatable, Sendable {
    public let policy: AmbientLightPolicy
    /// Smoothed brightness in 0...1, or `nil` while it is unknown.
    public private(set) var level: Double?
    /// Whether the room is dark, or `nil` while it is unknown.
    public private(set) var isRoomDark: Bool?
    private var smoothed: Double?
    private var firstSampleAt: TimeInterval?
    private var lastSampleAt: TimeInterval?
    private var flipPendingSince: TimeInterval?

    public init(policy: AmbientLightPolicy = AmbientLightPolicy()) {
        self.policy = policy
    }

    /// Forgets everything, for example when the camera stops.
    public mutating func reset() {
        self = AmbientLightEstimator(policy: policy)
    }

    /// Feeds one frame. Returns true when `level` or `isRoomDark` changed.
    @discardableResult
    public mutating func update(with sample: SceneLightSample?, at timestamp: TimeInterval) -> Bool {
        guard let sample, let raw = SceneBrightness.level(for: sample) else { return false }
        let startedAt = min(firstSampleAt ?? timestamp, timestamp)
        firstSampleAt = startedAt
        guard timestamp - startedAt >= policy.settlingTime else { return false }

        guard let previous = smoothed, let lastSampleAt, let reported = level, let dark = isRoomDark else {
            smoothed = raw
            lastSampleAt = timestamp
            level = raw
            isRoomDark = raw <= policy.darkEnter
            return true
        }
        let elapsed = max(0, timestamp - lastSampleAt)
        let current = policy.smoothingTime > 0
            ? previous + (1 - exp(-elapsed / policy.smoothingTime)) * (raw - previous)
            : raw
        smoothed = current
        self.lastSampleAt = timestamp

        var changed = false
        if abs(current - reported) >= policy.reportingStep, current != reported {
            level = current
            changed = true
        }
        let isPastBound = dark ? current >= policy.darkExit : current <= policy.darkEnter
        guard isPastBound else {
            flipPendingSince = nil
            return changed
        }
        // A timestamp that went backward restarts the wait.
        let pendingSince = min(flipPendingSince ?? timestamp, timestamp)
        flipPendingSince = pendingSince
        if timestamp - pendingSince >= policy.minimumDwell {
            isRoomDark = !dark
            flipPendingSince = nil
            changed = true
        }
        return changed
    }
}
