import Foundation
import HomePadCore

/// Where the viewer's face is in front of the screen. `x` grows toward the viewer's right and `y`
/// grows downward, both 0...1, with 0.5 meaning straight ahead.
public struct FacePosition: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? min(max(x, 0), 1) : 0.5
        self.y = y.isFinite ? min(max(y, 0), 1) : 0.5
    }

    public static let center = FacePosition(x: 0.5, y: 0.5)
}

public struct FlowPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// What the Flow face draws for one frame.
public struct FlowParameters: Equatable, Sendable {
    /// Where the shapes lean, 0...1 on both axes.
    public let focus: FlowPoint
    /// Radians. Advances with time; frozen when motion is reduced.
    public let phase: Double
    /// How far shapes wander from rest, as a fraction of the canvas.
    public let amplitude: Double
    /// How strongly shapes lean toward the focus, 0...1.
    public let pull: Double
    /// Shapes grow slightly as someone comes close.
    public let scale: Double
}

public enum FlowField {
    public static let cycleSeconds: Double = 24

    /// With motion reduced the phase stops and the amplitude drops to zero, so the face is a
    /// still image that only leans toward the viewer.
    public static func parameters(position: FacePosition?, time: TimeInterval, proximity: Proximity, reduceMotion: Bool) -> FlowParameters {
        let focus = position ?? .center
        let near = proximity == .near
        return FlowParameters(
            focus: FlowPoint(x: focus.x, y: focus.y),
            phase: reduceMotion ? 0 : (time.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds) * 2 * .pi,
            amplitude: reduceMotion ? 0 : (near ? 0.035 : 0.05),
            pull: position == nil ? 0 : (near ? 0.5 : 0.3),
            scale: near ? 1.06 : 1
        )
    }

    /// Where shape `index` of `count` is drawn, given its rest position. Each shape orbits its
    /// rest point on its own phase offset and leans toward the focus.
    public static func displaced(rest: FlowPoint, index: Int, count: Int, parameters: FlowParameters) -> FlowPoint {
        let offset = count > 0 ? Double(index) / Double(count) * 2 * .pi : 0
        let wobbleX = cos(parameters.phase + offset) * parameters.amplitude
        let wobbleY = sin(parameters.phase * 2 + offset) * parameters.amplitude
        let leanX = (parameters.focus.x - 0.5) * parameters.pull * 0.2
        let leanY = (parameters.focus.y - 0.5) * parameters.pull * 0.2
        return FlowPoint(x: rest.x + wobbleX + leanX, y: rest.y + wobbleY + leanY)
    }

    /// Control points for a `columns` by `rows` background mesh. Corners stay put, edge points
    /// slide along their edge, and interior points drift and lean toward the focus.
    public static func meshPoints(columns: Int, rows: Int, parameters: FlowParameters) -> [FlowPoint] {
        guard columns > 1, rows > 1 else { return [] }
        var points: [FlowPoint] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let rest = FlowPoint(x: Double(column) / Double(columns - 1), y: Double(row) / Double(rows - 1))
                let onVerticalEdge = column == 0 || column == columns - 1
                let onHorizontalEdge = row == 0 || row == rows - 1
                let moved = displaced(rest: rest, index: row * columns + column, count: columns * rows, parameters: parameters)
                points.append(FlowPoint(
                    x: onVerticalEdge ? rest.x : min(max(moved.x, 0.05), 0.95),
                    y: onHorizontalEdge ? rest.y : min(max(moved.y, 0.05), 0.95)
                ))
            }
        }
        return points
    }
}

/// Eases the focus toward the latest face position so camera jitter does not shake the face.
public struct FlowFocusSmoother: Equatable, Sendable {
    public private(set) var current: FacePosition
    /// Larger is snappier. The focus covers about 63 percent of the gap in `1 / responsiveness` seconds.
    public let responsiveness: Double

    public init(current: FacePosition = .center, responsiveness: Double = 3) {
        self.current = current
        self.responsiveness = max(0, responsiveness)
    }

    /// With no target the focus eases back to the center.
    @discardableResult
    public mutating func advance(toward target: FacePosition?, deltaTime: TimeInterval) -> FacePosition {
        let goal = target ?? .center
        let step = 1 - exp(-responsiveness * max(0, deltaTime.isFinite ? deltaTime : 0))
        current = FacePosition(
            x: current.x + (goal.x - current.x) * step,
            y: current.y + (goal.y - current.y) * step
        )
        return current
    }
}
