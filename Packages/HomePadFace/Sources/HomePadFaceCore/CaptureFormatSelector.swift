import Foundation

/// One camera format the capture device offers.
public struct CaptureFormatCandidate: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let maximumFrameRate: Double
    public let supportsDepth: Bool

    public init(width: Int, height: Int, maximumFrameRate: Double, supportsDepth: Bool) {
        self.width = width
        self.height = height
        self.maximumFrameRate = maximumFrameRate
        self.supportsDepth = supportsDepth
    }
}

/// Picks a camera format for recognition: enough pixels for a face across the room, but no more,
/// because the camera runs for hours.
public struct CaptureFormatSelector: Equatable, Sendable {
    public var targetWidth: Int
    public var minimumFrameRate: Double

    public init(targetWidth: Int = 1280, minimumFrameRate: Double = 15) {
        self.targetWidth = targetWidth
        self.minimumFrameRate = minimumFrameRate
    }

    /// Index of the best candidate, or `nil` when none is fast enough. Formats with depth win
    /// when `prefersDepth` is set. Among the rest, the smallest format at least `targetWidth`
    /// wide wins, then the widest one below it.
    public func select(from candidates: [CaptureFormatCandidate], prefersDepth: Bool) -> Int? {
        let usable = candidates.enumerated().filter { $0.element.maximumFrameRate >= minimumFrameRate }
        let withDepth = usable.filter { $0.element.supportsDepth }
        let pool = prefersDepth && !withDepth.isEmpty ? withDepth : usable
        func area(_ candidate: CaptureFormatCandidate) -> Int { candidate.width * candidate.height }
        let wideEnough = pool.filter { $0.element.width >= targetWidth }
        if let smallest = wideEnough.min(by: { area($0.element) < area($1.element) }) {
            return smallest.offset
        }
        return pool.max { area($0.element) < area($1.element) }?.offset
    }
}
