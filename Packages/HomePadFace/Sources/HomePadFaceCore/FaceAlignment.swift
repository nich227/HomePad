import Foundation

/// A 2D rotation, uniform scale, and translation: `x' = a*x - b*y + tx`, `y' = b*x + a*y + ty`.
public struct SimilarityTransform: Equatable, Sendable {
    public let a: Double
    public let b: Double
    public let tx: Double
    public let ty: Double

    public init(a: Double, b: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.tx = tx
        self.ty = ty
    }

    public var scale: Double { (a * a + b * b).squareRoot() }
    public var rotation: Double { atan2(b, a) }

    public func apply(_ point: CGPoint) -> CGPoint {
        CGPoint(x: a * point.x - b * point.y + tx, y: b * point.x + a * point.y + ty)
    }

    public var affineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }
}

/// The five points face embedding models are aligned on. "Left" and "right" mean the side of
/// the upright image, not the person's own left and right: `leftEye` is the eye with the smaller
/// x, which is the person's right eye when they face the camera. Assigning by position instead
/// of by the detector's landmark names keeps the crop unflipped for mirrored camera images.
/// Points use a top-left origin with y growing downward.
public struct FacePoints: Equatable, Sendable {
    public var leftEye: CGPoint
    public var rightEye: CGPoint
    public var nose: CGPoint?
    public var leftMouth: CGPoint?
    public var rightMouth: CGPoint?

    public init(
        leftEye: CGPoint,
        rightEye: CGPoint,
        nose: CGPoint? = nil,
        leftMouth: CGPoint? = nil,
        rightMouth: CGPoint? = nil
    ) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.nose = nose
        self.leftMouth = leftMouth
        self.rightMouth = rightMouth
    }

    /// All five points in template order, or `nil` when one is missing.
    var allFive: [CGPoint]? {
        guard let nose, let leftMouth, let rightMouth else { return nil }
        return [leftEye, rightEye, nose, leftMouth, rightMouth]
    }

    /// Derives the five points from detector landmarks, which do not name them directly.
    ///
    /// - Eye centers are the centroids of the eye outlines, or the pupils when an outline is
    ///   missing. The two eyes may come in either order.
    /// - The nose tip is the nose-crest point farthest from the midpoint between the eyes,
    ///   because the crest runs from between the eyes down to the tip.
    /// - The mouth corners are the outer-lip points farthest apart along the line through the
    ///   eyes.
    ///
    /// These are approximations of the points alignment templates were built from. Returns `nil`
    /// when an eye cannot be located.
    public static func derived(
        eyeOutlines: ([CGPoint], [CGPoint]),
        pupils: (CGPoint?, CGPoint?) = (nil, nil),
        noseCrest: [CGPoint] = [],
        outerLips: [CGPoint] = []
    ) -> FacePoints? {
        guard
            let first = EyeGeometry.centroid(of: eyeOutlines.0) ?? pupils.0,
            let second = EyeGeometry.centroid(of: eyeOutlines.1) ?? pupils.1
        else { return nil }
        let (leftEye, rightEye) = first.x <= second.x ? (first, second) : (second, first)
        var points = FacePoints(leftEye: leftEye, rightEye: rightEye)
        let middle = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        points.nose = noseCrest.max { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }
        let axis = CGPoint(x: rightEye.x - leftEye.x, y: rightEye.y - leftEye.y)
        func along(_ point: CGPoint) -> Double { point.x * axis.x + point.y * axis.y }
        if outerLips.count >= 2 {
            points.leftMouth = outerLips.min { along($0) < along($1) }
            points.rightMouth = outerLips.max { along($0) < along($1) }
        }
        return points
    }
}

/// Maps a detected face onto the canonical crop that face embedding models are trained on.
public enum FaceAlignment {
    /// Side of the square the reference points are defined in.
    public static let referenceSize: Double = 112

    /// The standard five-point template for a 112 by 112 crop (the one used by ArcFace and by
    /// OpenCV for SFace), scaled to `outputSize`.
    public static func referencePoints(outputSize: Double) -> FacePoints {
        let points = referenceArray(outputSize: outputSize)
        return FacePoints(leftEye: points[0], rightEye: points[1], nose: points[2], leftMouth: points[3], rightMouth: points[4])
    }

    /// Left eye, right eye, nose, left mouth corner, right mouth corner.
    private static func referenceArray(outputSize: Double) -> [CGPoint] {
        let factor = outputSize / referenceSize
        return [(38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366), (41.5493, 92.3655), (70.7299, 92.2041)]
            .map { CGPoint(x: $0.0 * factor, y: $0.1 * factor) }
    }

    /// Least-squares similarity transform from the detected points to the reference points. Uses
    /// all five points when they are present and the two eyes otherwise. Returns `nil` for
    /// unusable input.
    public static func transform(from detected: FacePoints, outputSize: Double) -> SimilarityTransform? {
        let source = detected.allFive ?? [detected.leftEye, detected.rightEye]
        let target = Array(referenceArray(outputSize: outputSize).prefix(source.count))
        let count = Double(source.count)
        let sourceMean = CGPoint(x: source.reduce(0) { $0 + $1.x } / count, y: source.reduce(0) { $0 + $1.y } / count)
        let targetMean = CGPoint(x: target.reduce(0) { $0 + $1.x } / count, y: target.reduce(0) { $0 + $1.y } / count)
        var spread = 0.0, dot = 0.0, cross = 0.0
        for (point, goal) in zip(source, target) {
            let px = point.x - sourceMean.x, py = point.y - sourceMean.y
            let qx = goal.x - targetMean.x, qy = goal.y - targetMean.y
            spread += px * px + py * py
            dot += px * qx + py * qy
            cross += px * qy - py * qx
        }
        guard outputSize > 0, spread.isFinite, spread > 1e-9 else { return nil }
        let a = dot / spread, b = cross / spread
        return SimilarityTransform(
            a: a,
            b: b,
            tx: targetMean.x - (a * sourceMean.x - b * sourceMean.y),
            ty: targetMean.y - (b * sourceMean.x + a * sourceMean.y)
        )
    }

    /// The same mapping for images whose origin is the bottom-left corner with y growing upward,
    /// which is how Core Image addresses pixels. The result maps a source image of height
    /// `sourceHeight` into an `outputSize` square at the origin.
    public static func bottomLeftOriginTransform(
        _ transform: SimilarityTransform,
        sourceHeight: Double,
        outputSize: Double
    ) -> CGAffineTransform {
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let flipOutput = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: outputSize)
        return flipSource.concatenating(transform.affineTransform).concatenating(flipOutput)
    }
}
