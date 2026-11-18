import Foundation
import HomePadCore

/// Very tall, narrow digits with one stroke width, for the Photos face. System fonts do not come
/// this narrow, and stretching one makes its horizontal strokes too heavy.
public enum TallDigits {
    public struct Stroke: Equatable, Sendable {
        public let points: [DialPoint]
        public let isClosed: Bool
    }

    /// Centerlines of a digit in a box one unit wide and `aspect` units tall, origin top leading.
    /// The caller strokes them with a round join. Anything other than 0...9 has no strokes.
    public static func strokes(for digit: Int, aspect: Double = 7) -> [Stroke] {
        let h = max(aspect, 3)
        let waist = h * 0.47
        var pen = Pen()
        switch digit {
        case 0:
            pen.arc(0.5, 180, 360)
            pen.arc(h - 0.5, 0, 180)
            pen.close()
        case 1:
            pen.line(0, min(1.15, h * 0.2))
            pen.line(0.72, 0)
            pen.line(0.72, h)
        case 2:
            pen.arc(0.5, 180, 360)
            pen.line(1, 0.5 + h * 0.14)
            pen.line(0, h)
            pen.line(1, h)
        case 3:
            pen.arc(0.5, 180, 360)
            pen.arc(waist - 0.5, 0, 90)
            pen.arc(waist + 0.5, 270, 360)
            pen.arc(h - 0.5, 0, 180)
        case 4:
            pen.line(0.72, 0)
            pen.line(0, h * 0.68)
            pen.line(1, h * 0.68)
            pen.lift()
            pen.line(0.72, 0)
            pen.line(0.72, h)
        case 5:
            pen.line(1, 0)
            pen.line(0, 0)
            pen.line(0, h * 0.42)
            pen.arc(h * 0.42, 180, 360)
            pen.arc(h - 0.5, 0, 180)
        case 6:
            pen.arc(0.5, 360, 180)
            pen.arc(h - 0.5, 180, 0)
            pen.arc(h * 0.52, 360, 180)
        case 7:
            pen.line(0, 0)
            pen.line(1, 0)
            pen.line(0.28, h)
        case 8:
            pen.arc(0.5, 180, 360)
            pen.arc(waist - 0.5, 0, 180)
            pen.close()
            pen.arc(waist + 0.5, 180, 360)
            pen.arc(h - 0.5, 0, 180)
            pen.close()
        case 9:
            pen.arc(0.5, 180, 360)
            pen.arc(h * 0.6 - 0.5, 0, 180)
            pen.close()
            pen.line(1, 0.5)
            pen.line(1, h - 0.5)
            pen.arc(h - 0.5, 0, 180)
        default:
            break
        }
        pen.lift()
        return pen.strokes
    }

    /// Collects points into strokes. Arcs are half a unit in radius, centered on the box, and
    /// are sampled into short segments so the caller only draws lines.
    private struct Pen {
        var strokes: [Stroke] = []
        private var points: [DialPoint] = []

        mutating func line(_ x: Double, _ y: Double) {
            points.append(DialPoint(x: x, y: y))
        }

        /// Angles are in degrees on screen: 0 is right, 90 is down, 180 is left, 270 is up.
        mutating func arc(_ centerY: Double, _ from: Double, _ to: Double) {
            let steps = 12
            for step in 0...steps {
                let radians = (from + (to - from) * Double(step) / Double(steps)) * .pi / 180
                points.append(DialPoint(x: 0.5 + cos(radians) / 2, y: centerY + sin(radians) / 2))
            }
        }

        mutating func close() {
            strokes.append(Stroke(points: points, isClosed: true))
            points = []
        }

        mutating func lift() {
            if !points.isEmpty {
                strokes.append(Stroke(points: points, isClosed: false))
            }
            points = []
        }
    }
}

/// How large the views from other packages should draw their text on the hub canvas. They use
/// ordinary text styles, which are sized for a screen held in the hand.
public enum SlotTextScale {
    /// Body text size at each Dynamic Type step from Large upward.
    public static let bodySizes: [Double] = [17, 19, 21, 23, 28, 33, 40, 47, 53]
    /// Body text should be about this fraction of the canvas side.
    public static let targetFraction = 0.034

    /// The number of Dynamic Type steps above Large that suits a canvas of this side.
    public static func step(forCanvasSide side: Double) -> Int {
        let target = side * targetFraction
        return bodySizes.lastIndex { $0 <= target } ?? 0
    }
}

/// Switches set only by the UI tests, through the launch environment. Every one is off unless
/// its variable is present, and release builds never read them.
public struct HubTestHooks: Equatable, Sendable {
    public enum Audience: String, Sendable {
        case guest, manual, recognized
    }

    /// Keep layouts, timers, alarms, and photos in memory, so a run starts clean and leaves
    /// nothing behind.
    public let isEphemeral: Bool
    /// Use a sample household, home, music, weather, and recipe instead of the real services.
    public let usesSampleData: Bool
    public let audience: Audience?
    public let proximity: Proximity?
    public let canvas: CanvasMode?
    public let forcesNight: Bool
    public let skipsWelcome: Bool
    /// Behave as if the camera matched a member without a liveness proof and the device's own
    /// biometrics are offered, on hardware that has none.
    public let offersDeviceUnlock: Bool
    /// Frame the whole app to this size, to capture the layout of a display that cannot be
    /// simulated here.
    public let viewport: TestViewport?
    /// Play this role whatever the device and Settings say.
    public let role: DeviceRole?
    /// Lay the hub out as if a fold divides the display in two.
    public let foldsHub: Bool
    /// Draw glass as solid fills, as Reduce Transparency does. A test cannot turn that setting on.
    public let usesSolidGlass: Bool
    /// Run the shell's animations this many times slower, so a test can catch them part way.
    public let slowMotion: Double?
    /// Supply a stand-in assistant, so the control that opens one and its host can be captured
    /// before the real one exists.
    public let showsSampleAssistant: Bool

    public static let none = HubTestHooks(environment: [:])

    public init(environment: [String: String]) {
        func flag(_ name: String) -> Bool {
            environment["HOMEPAD_UITEST_\(name)"] == "1"
        }
        usesSampleData = flag("SAMPLE")
        isEphemeral = flag("EPHEMERAL") || usesSampleData
        audience = environment["HOMEPAD_UITEST_AUDIENCE"].flatMap(Audience.init(rawValue:))
        proximity = environment["HOMEPAD_UITEST_PROXIMITY"].flatMap(Proximity.init(rawValue:))
        canvas = environment["HOMEPAD_UITEST_CANVAS"].flatMap(CanvasMode.init(rawValue:))
        forcesNight = flag("NIGHT")
        skipsWelcome = flag("SKIP_WELCOME")
        offersDeviceUnlock = flag("DEVICE_UNLOCK")
        viewport = environment["HOMEPAD_UITEST_VIEWPORT"].flatMap(TestViewport.init)
        role = environment["HOMEPAD_UITEST_ROLE"].flatMap(DeviceRole.init(rawValue:))
        foldsHub = flag("FOLD")
        usesSolidGlass = flag("SOLID_GLASS")
        showsSampleAssistant = flag("ASSISTANT")
        slowMotion = environment["HOMEPAD_UITEST_SLOW_MOTION"].flatMap(Double.init).flatMap { $0 >= 1 ? $0 : nil }
    }
}
