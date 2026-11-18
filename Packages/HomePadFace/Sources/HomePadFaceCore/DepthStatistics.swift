import Foundation

/// One depth reading inside the face box. `x` and `y` are 0...1 across the box. `depth` is in
/// meters; a non-finite or non-positive value marks a pixel the sensor could not measure.
public struct DepthPoint: Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let depth: Float

    public init(x: Float, y: Float, depth: Float) {
        self.x = x
        self.y = y
        self.depth = depth
    }
}

/// Summary of the depth relief of a face region. A printed photo or a screen is close to a plane
/// even when tilted, so its plane residual and center relief are near zero. A real face is not.
public struct FaceDepthStatistics: Equatable, Sendable {
    /// Readings farther than this from the median are background or sensor glitches, not face.
    public static let maximumSpreadFromMedian: Float = 0.15
    static let minimumPointsForPlane = 6

    public let sampleCount: Int
    public let validCount: Int
    /// Meters from the camera.
    public let medianDepth: Float
    /// Root mean square distance of the readings from their best-fit plane, in meters.
    public let planeResidual: Float
    /// Median depth of the outer ring minus median depth of the center, in meters. Positive when
    /// the center (nose) is closer to the camera than the edges (cheeks, temples).
    public let centerRelief: Float

    public init(sampleCount: Int, validCount: Int, medianDepth: Float, planeResidual: Float, centerRelief: Float) {
        self.sampleCount = sampleCount
        self.validCount = validCount
        self.medianDepth = medianDepth
        self.planeResidual = planeResidual
        self.centerRelief = centerRelief
    }

    public var validFraction: Float {
        sampleCount > 0 ? Float(validCount) / Float(sampleCount) : 0
    }

    /// - Parameters:
    ///   - centerRadius: readings within this distance of the box center form the center group.
    ///   - ringInnerRadius: readings at least this far from the box center form the outer ring.
    public init(points: [DepthPoint], centerRadius: Float = 0.18, ringInnerRadius: Float = 0.3) {
        let measured = points.filter { $0.depth.isFinite && $0.depth > 0 }
        let median = Self.median(measured.map(\.depth))
        let valid = measured.filter { abs($0.depth - median) <= Self.maximumSpreadFromMedian }
        func radius(_ point: DepthPoint) -> Float {
            ((point.x - 0.5) * (point.x - 0.5) + (point.y - 0.5) * (point.y - 0.5)).squareRoot()
        }
        let center = valid.filter { radius($0) <= centerRadius }.map(\.depth)
        let ring = valid.filter { radius($0) >= ringInnerRadius }.map(\.depth)
        self.init(
            sampleCount: points.count,
            validCount: valid.count,
            medianDepth: median,
            planeResidual: Self.planeResidual(valid),
            centerRelief: center.isEmpty || ring.isEmpty ? 0 : Self.median(ring) - Self.median(center)
        )
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Least-squares plane `depth = a*x + b*y + c`, then the RMS of what the plane leaves over.
    /// Returns 0 when the points cannot define a plane.
    static func planeResidual(_ points: [DepthPoint]) -> Float {
        guard points.count >= minimumPointsForPlane else { return 0 }
        let count = Double(points.count)
        let meanX = points.reduce(0) { $0 + Double($1.x) } / count
        let meanY = points.reduce(0) { $0 + Double($1.y) } / count
        let meanZ = points.reduce(0) { $0 + Double($1.depth) } / count
        var sxx = 0.0, sxy = 0.0, syy = 0.0, sxz = 0.0, syz = 0.0
        for point in points {
            let dx = Double(point.x) - meanX, dy = Double(point.y) - meanY, dz = Double(point.depth) - meanZ
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
            sxz += dx * dz
            syz += dy * dz
        }
        let determinant = sxx * syy - sxy * sxy
        guard determinant > 1e-12 else { return 0 }
        let a = (sxz * syy - syz * sxy) / determinant
        let b = (syz * sxx - sxz * sxy) / determinant
        let squared = points.reduce(0.0) { sum, point in
            let rest = Double(point.depth) - meanZ - a * (Double(point.x) - meanX) - b * (Double(point.y) - meanY)
            return sum + rest * rest
        }
        return Float((squared / count).squareRoot())
    }
}
