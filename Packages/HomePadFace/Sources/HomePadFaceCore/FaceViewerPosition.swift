import Foundation

/// Where the viewer's face is, as they would see themselves in a mirror filling the screen.
///
/// `x` and `y` are 0...1 with the origin at the top-left. Because it is a mirror view, a person
/// who moves to their own left moves `x` toward 0, and a person who moves up moves `y` toward 0.
public struct FaceViewerPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double

    /// Values outside 0...1 are clamped, and a value that is not a number becomes the center.
    public init(x: Double, y: Double) {
        self.x = x.isNaN ? 0.5 : min(1, max(0, x))
        self.y = y.isNaN ? 0.5 : min(1, max(0, y))
    }

    /// The mirror-view position of a face box from the camera.
    ///
    /// - Parameter uprightCameraBox: the face box normalized to the camera image, after the
    ///   image has been turned upright, with the origin at the bottom-left, and not mirrored.
    ///   That is the camera's own view: the person's left is on the image's right. This flips it
    ///   horizontally for the mirror view and vertically for the top-left origin.
    public init(uprightCameraBox box: CGRect) {
        self.init(x: 1 - box.midX, y: 1 - box.midY)
    }

    func distance(to other: FaceViewerPosition) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

/// Steadies the viewer position. A low-pass filter removes frame-to-frame jitter, small moves
/// are not reported at all, and a face that drops out for a frame or two keeps its position.
public struct FacePositionSmoother: Equatable, Sendable {
    /// Weight of each new sample, in 0...1. Lower is steadier and slower to follow.
    public let responsiveness: Double
    /// The filtered position must move this far from the reported one before it is reported.
    public let minimumChange: Double
    /// Consecutive frames without a face before the position is cleared.
    public let missesToClear: Int

    /// The position to show, or `nil` when no face is present.
    public private(set) var position: FaceViewerPosition?
    private var filtered: FaceViewerPosition?
    private var misses = 0

    public init(responsiveness: Double = 0.35, minimumChange: Double = 0.01, missesToClear: Int = 3) {
        self.responsiveness = min(1, max(0.01, responsiveness))
        self.minimumChange = max(0, minimumChange)
        self.missesToClear = max(1, missesToClear)
    }

    /// Feeds one frame. Returns true when `position` changed.
    @discardableResult
    public mutating func update(with sample: FaceViewerPosition?) -> Bool {
        guard let sample else {
            misses += 1
            guard misses >= missesToClear, position != nil else { return false }
            reset()
            return true
        }
        misses = 0
        guard let previous = filtered, let reported = position else {
            filtered = sample
            position = sample
            return true
        }
        let next = FaceViewerPosition(
            x: previous.x + responsiveness * (sample.x - previous.x),
            y: previous.y + responsiveness * (sample.y - previous.y)
        )
        filtered = next
        guard next.distance(to: reported) >= minimumChange else { return false }
        position = next
        return true
    }

    /// Clears the position at once, for example when the camera stops.
    public mutating func reset() {
        position = nil
        filtered = nil
        misses = 0
    }
}
