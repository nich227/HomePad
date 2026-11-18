import Foundation

public enum EyeGeometry {
    /// Height over width of an eye outline, measured along and across the line between its two
    /// farthest points so head roll does not change the result. About 0.3 for an open eye and
    /// near 0 for a closed one. Returns `nil` for fewer than three points or a degenerate outline.
    public static func openness(outline: [CGPoint]) -> Float? {
        guard outline.count >= 3 else { return nil }
        var width = 0.0
        var axis = CGPoint.zero
        for (index, first) in outline.enumerated() {
            for second in outline.dropFirst(index + 1) {
                let distance = hypot(second.x - first.x, second.y - first.y)
                if distance > width {
                    width = distance
                    axis = CGPoint(x: (second.x - first.x) / distance, y: (second.y - first.y) / distance)
                }
            }
        }
        guard width.isFinite, width > 1e-9 else { return nil }
        let across = outline.map { $0.y * axis.x - $0.x * axis.y }
        let height = across.reduce(-CGFloat.infinity, max) - across.reduce(CGFloat.infinity, min)
        return Float(height / width)
    }

    /// Mean openness of the outlines that could be measured.
    public static func meanOpenness(outlines: [[CGPoint]]) -> Float? {
        let values = outlines.compactMap(openness(outline:))
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    public static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let count = Double(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
    }
}
