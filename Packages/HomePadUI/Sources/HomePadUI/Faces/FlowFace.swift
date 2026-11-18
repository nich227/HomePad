import HomePadCore
import HomePadUICore
import SwiftUI

/// Holds the eased focus between frames. A plain reference so advancing it while drawing does
/// not count as a view state change.
@MainActor
final class FlowFocus {
    private var smoother = FlowFocusSmoother()
    private var lastDate: Date?

    func advance(toward target: FacePosition?, at date: Date) -> FacePosition {
        let delta = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        return smoother.advance(toward: target, deltaTime: min(max(delta, 0), 0.5))
    }
}

/// The time as soft liquid shapes drifting on a pink and blue field. The shapes lean toward
/// whoever is in front of the screen.
struct FlowFace: View {
    let date: Date
    let facePosition: FacePosition?
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hubIsNight) private var isNight
    @Environment(HouseholdSession.self) private var session
    @State private var focus = FlowFocus()

    private static let pink = Color(red: 1, green: 0.44, blue: 0.72)
    private static let blue = Color(red: 0.36, green: 0.52, blue: 1)
    private static let lavender = Color(red: 0.86, green: 0.78, blue: 0.97)

    /// Rest positions of the four digit shapes: hours on top, minutes below.
    private static let stackedRests = [FlowPoint(x: 0.3, y: 0.3), FlowPoint(x: 0.68, y: 0.3), FlowPoint(x: 0.32, y: 0.72), FlowPoint(x: 0.7, y: 0.72)]
    /// On a wide screen the four digits sit in one row.
    private static let rowRests = [FlowPoint(x: 0.16, y: 0.5), FlowPoint(x: 0.38, y: 0.5), FlowPoint(x: 0.62, y: 0.5), FlowPoint(x: 0.84, y: 0.5)]

    private var digitRests: [FlowPoint] {
        metrics.isLandscape ? Self.rowRests : Self.stackedRests
    }

    /// Loose drops sit toward the edges. One between two digits reads as a decimal point.
    private static let satelliteRests = [FlowPoint(x: 0.1, y: 0.52), FlowPoint(x: 0.9, y: 0.5), FlowPoint(x: 0.5, y: 0.07), FlowPoint(x: 0.92, y: 0.9)]

    var body: some View {
        let target = preferences.faces.flowReactsToPresence ? facePosition : nil
        let eased = focus.advance(toward: target, at: date)
        let parameters = FlowField.parameters(
            position: target == nil ? nil : eased,
            time: date.timeIntervalSinceReferenceDate,
            proximity: session.proximity,
            reduceMotion: reduceMotion
        )
        let columns = TimeTextPolicy.digitColumns(for: ClockReading(date: date, calendar: calendar), hourCycle: units.hourCycle)
        ZStack {
            if isNight {
                Color.black
            } else {
                field(parameters)
            }
            ZStack {
                RadialGradient(
                    colors: [Self.blue, Self.pink],
                    center: UnitPoint(x: parameters.focus.x, y: parameters.focus.y),
                    startRadius: metrics.pt(4),
                    endRadius: metrics.pt(70)
                )
                LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
            }
            .mask { shapes(columns: columns, parameters: parameters) }
            .shadow(color: Self.pink.opacity(0.5), radius: metrics.pt(2.5))
            if density.showsLabels {
                Text(FaceText.dateLine(date, calendar: calendar, density: density, locale: locale))
                    .font(.system(size: metrics.text(3), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, metrics.pt(3))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
    }

    private func field(_ parameters: FlowParameters) -> some View {
        let points = FlowField.meshPoints(columns: 3, rows: 3, parameters: parameters).map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        return MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: [
                Self.lavender, Color(red: 0.96, green: 0.8, blue: 0.93), Self.lavender,
                Color(red: 1, green: 0.66, blue: 0.86), Color(red: 1, green: 0.5, blue: 0.8), Color(red: 0.92, green: 0.7, blue: 0.96),
                Self.lavender, Color(red: 0.98, green: 0.74, blue: 0.9), Self.lavender,
            ]
        )
        .accessibilityHidden(true)
    }

    /// Digits and loose drops drawn blurred, then cut back to a hard edge, so shapes that come
    /// close flow into each other.
    private func shapes(columns: [Int], parameters: FlowParameters) -> some View {
        let hidesLeadingZero = units.hourCycle == .twelve && columns[0] == 0
        return Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: min(size.width, size.height) * 0.016))
            context.drawLayer { layer in
                let unit = min(size.width, size.height)
                let rests = digitRests
                let font = Font.system(size: unit * 0.44 * parameters.scale, weight: .black, design: .rounded)
                let count = rests.count + Self.satelliteRests.count
                for (index, rest) in rests.enumerated() where !(index == 0 && hidesLeadingZero) {
                    let moved = FlowField.displaced(rest: rest, index: index, count: count, parameters: parameters)
                    layer.draw(
                        Text(verbatim: "\(columns[index])").font(font).foregroundStyle(.white),
                        at: CGPoint(x: moved.x * size.width, y: moved.y * size.height)
                    )
                }
                for (index, rest) in Self.satelliteRests.enumerated() {
                    let moved = FlowField.displaced(rest: rest, index: rests.count + index, count: count, parameters: parameters)
                    let radius = unit * (0.035 + 0.012 * CGFloat(index % 3))
                    let rect = CGRect(x: moved.x * size.width - radius, y: moved.y * size.height - radius, width: radius * 2, height: radius * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
    }
}
