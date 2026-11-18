import HomePadUICore
import SwiftUI

/// Draws clock hands in the style the hub uses everywhere: a thin stem at the center and a
/// rounded bar out to the tip.
enum ClockDrawing {
    static func point(center: CGPoint, radius: CGFloat, degrees: Double, fraction: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(sin(radians)) * radius * fraction, y: center.y - CGFloat(cos(radians)) * radius * fraction)
    }

    static func hand(
        _ context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        degrees: Double,
        length: CGFloat,
        width: CGFloat,
        color: Color
    ) {
        var stem = Path()
        stem.move(to: center)
        stem.addLine(to: point(center: center, radius: radius, degrees: degrees, fraction: 0.16))
        context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: width * 0.38, lineCap: .round))
        var bar = Path()
        bar.move(to: point(center: center, radius: radius, degrees: degrees, fraction: 0.14))
        bar.addLine(to: point(center: center, radius: radius, degrees: degrees, fraction: length))
        context.stroke(bar, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    static func secondHand(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, degrees: Double, length: CGFloat, width: CGFloat, color: Color) {
        var line = Path()
        line.move(to: point(center: center, radius: radius, degrees: degrees + 180, fraction: 0.12))
        line.addLine(to: point(center: center, radius: radius, degrees: degrees, fraction: length))
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        let dot = width * 1.6
        context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)), with: .color(color))
    }

    static func ticks(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, hoursOnly: Bool, color: Color, width: CGFloat) {
        let count = hoursOnly ? 12 : 60
        for index in 0..<count {
            let isHour = ClockDial.isHourTick(index: index, count: count)
            let degrees = ClockDial.tickAngle(index: index, count: count)
            var tick = Path()
            tick.move(to: point(center: center, radius: radius, degrees: degrees, fraction: isHour ? 0.84 : 0.93))
            tick.addLine(to: point(center: center, radius: radius, degrees: degrees, fraction: 0.98))
            context.stroke(tick, with: .color(color.opacity(isHour ? 1 : 0.55)), style: StrokeStyle(lineWidth: isHour ? width : width * 0.6, lineCap: .round))
        }
    }
}

/// A round analog clock used as a tile on faces and in widgets.
struct AnalogDial: View {
    enum Markers {
        case numerals
        case hourTicks
    }

    let date: Date
    var markers: Markers = .hourTicks
    var dialColor: Color = .clear
    var inkColor: Color = .white
    var secondColor: Color = Color(.orange)
    var showsSecondHand = true
    @Environment(\.calendar) private var calendar

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let angles = ClockHandAngles(reading: ClockReading(date: date, calendar: calendar), sweeps: false)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(dialColor))
            switch markers {
            case .hourTicks:
                ClockDrawing.ticks(context, center: center, radius: radius, hoursOnly: true, color: inkColor, width: radius * 0.035)
            case .numerals:
                ClockDrawing.ticks(context, center: center, radius: radius, hoursOnly: false, color: inkColor.opacity(0.7), width: radius * 0.018)
                for hour in 1...12 {
                    let position = ClockDrawing.point(center: center, radius: radius, degrees: ClockDial.numeralAngle(hour: hour), fraction: 0.72)
                    context.draw(Text(verbatim: "\(hour)").font(.system(size: radius * 0.2, weight: .semibold, design: .rounded)).foregroundStyle(inkColor), at: position)
                }
            }
            ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.hour, length: 0.5, width: radius * 0.075, color: inkColor)
            ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.minute, length: 0.82, width: radius * 0.075, color: inkColor)
            if showsSecondHand {
                ClockDrawing.secondHand(context, center: center, radius: radius, degrees: angles.second, length: 0.86, width: radius * 0.02, color: secondColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
    }
}

/// Text helpers shared by faces.
enum FaceText {
    static func clock(_ date: Date, calendar: Calendar, density: FaceDensity, units: HubUnits, showsSeconds: Bool = false) -> ClockText {
        TimeTextPolicy.clockText(
            for: ClockReading(date: date, calendar: calendar),
            density: density,
            hourCycle: units.hourCycle,
            showsSeconds: showsSeconds
        )
    }

    static func dateLine(_ date: Date, calendar: Calendar, density: FaceDensity, locale: Locale) -> String {
        TimeTextPolicy.dateLine(for: date, style: TimeTextPolicy.dateLineStyle(for: density), calendar: calendar, locale: locale)
    }
}
