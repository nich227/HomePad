import Foundation
import HomePadCore

/// How much a face shows, from how far away the person is.
public enum FaceDensity: String, CaseIterable, Sendable {
    /// Across the room: the large numbers only.
    case glanceable
    /// On approach: labels, room names, and thumbnails appear.
    case contextual
    /// Within reach: the controls, at a size a finger can press.
    case detailed

    /// With adaptive detail off the hub always shows the detailed layout.
    public init(proximity: Proximity, adaptiveDetail: Bool = true) {
        guard adaptiveDetail else {
            self = .detailed
            return
        }
        switch proximity {
        case .far: self = .glanceable
        case .mid: self = .contextual
        case .near: self = .detailed
        }
    }

    /// Subtitles, room labels, and thumbnails: from the middle distance in.
    public var showsLabels: Bool { self != .glanceable }

    /// Steppers, sliders, and other small controls: only within reach.
    public var showsControls: Bool { self == .detailed }
}

/// The measurements the design is drawn to, in points on a 544 point square. `HubMetrics` scales
/// them by the shorter side of the space the hub has.
public enum DesignTokens {
    public static let baseSide = 544.0
    public static let outerMargin = 16.0
    public static let gutter = 12.0
    public static let tileRadius = 28.0
    public static let screenRadius = 60.0
    public static let heroFar = 96.0
    public static let heroNear = 72.0
    public static let tileTitle = 17.0
    public static let tileSubtitle = 14.0
    public static let subtitleOpacity = 0.72
    public static let iconBadge = 36.0
    public static let minimumTouch = 44.0
    public static let appIcon = 76.0
    public static let pillWidth = 260.0
    public static let pillHeight = 44.0
    public static let pillCardWidth = 512.0
    public static let pillCardHeight = 220.0

    /// A token scaled to a canvas whose shorter side is `side` points.
    public static func scaled(_ token: Double, side: Double) -> Double {
        token * side / baseSide
    }

    /// The hero number's size for a density, before scaling.
    public static func hero(for density: FaceDensity) -> Double {
        density == .glanceable ? heroFar : heroNear
    }
}

public enum HourCycle: String, Sendable {
    case twelve
    case twentyFour
}

/// The pieces of a digital time, split so a face can style each one.
public struct ClockText: Equatable, Sendable {
    public let hourText: String
    public let minuteText: String
    public let secondText: String?
    /// "AM" or "PM", only in twelve hour mode.
    public let periodText: String?

    public var digits: String { "\(hourText):\(minuteText)" }
}

public enum DateLineStyle: Equatable, Sendable {
    /// Weekday and day number, for example "Wed 1".
    case short
    /// Weekday, month, and day.
    case full
}

public enum TimeTextPolicy {
    /// Far away only hours and minutes are legible, so seconds and the period are dropped.
    public static func clockText(
        for reading: ClockReading,
        density: FaceDensity,
        hourCycle: HourCycle,
        showsSeconds: Bool = false
    ) -> ClockText {
        let hour = displayHour(for: reading, hourCycle: hourCycle)
        let period: String? = hourCycle == .twelve ? (reading.hour < 12 ? "AM" : "PM") : nil
        let detailed = density.showsLabels
        return ClockText(
            hourText: hourCycle == .twentyFour ? twoDigits(hour) : String(hour),
            minuteText: twoDigits(reading.minute),
            secondText: detailed && showsSeconds ? twoDigits(reading.second) : nil,
            periodText: detailed ? period : nil
        )
    }

    public static func dateLineStyle(for density: FaceDensity) -> DateLineStyle {
        density.showsLabels ? .full : .short
    }

    public static func dateLine(for date: Date, style: DateLineStyle, calendar: Calendar, locale: Locale) -> String {
        var format = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch style {
        case .short:
            format = format.weekday(.abbreviated).day()
        case .full:
            format = format.weekday(.wide).month(.wide).day()
        }
        return date.formatted(format)
    }

    /// How often a face must redraw. A face without seconds only changes on the minute.
    public static func refreshInterval(showsSeconds: Bool, sweeps: Bool) -> TimeInterval {
        if sweeps { return 1.0 / 30.0 }
        return showsSeconds ? 1 : 60
    }

    /// The four digits of a time for faces that draw each digit as its own shape.
    public static func digitColumns(for reading: ClockReading, hourCycle: HourCycle) -> [Int] {
        let hour = displayHour(for: reading, hourCycle: hourCycle)
        return [hour / 10, hour % 10, reading.minute / 10, reading.minute % 10]
    }

    /// A greeting keyed to the hour, shown above the profile name on the Home Screen.
    public static func greeting(forHour hour: Int) -> DayPart {
        switch hour {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }

    /// The hour as shown: 0...23, or 1...12 where midnight and noon read twelve.
    static func displayHour(for reading: ClockReading, hourCycle: HourCycle) -> Int {
        guard hourCycle == .twelve else { return reading.hour }
        let twelve = reading.hour % 12
        return twelve == 0 ? 12 : twelve
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}

public enum DayPart: String, Sendable {
    case morning, afternoon, evening, night
}

/// Countdown and elapsed-time text.
public enum DurationText {
    /// "4:05" under an hour, "1:04:05" from an hour up. Rounds up so a timer never shows 0:00 early.
    public static func countdown(_ interval: TimeInterval) -> String {
        clock(Int(max(0, interval).rounded(.up)))
    }

    /// Playback position, rounded down like a media scrubber.
    public static func elapsed(_ interval: TimeInterval) -> String {
        clock(Int(max(0, interval.isFinite ? interval : 0)))
    }

    /// The "15 MIN" caption under a countdown.
    public static func compact(_ interval: TimeInterval) -> DurationParts {
        let total = Int(max(0, interval).rounded())
        return DurationParts(hours: total / 3600, minutes: (total % 3600) / 60, seconds: total % 60)
    }

    private static func clock(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(TimeTextPolicy.twoDigits(minutes)):\(TimeTextPolicy.twoDigits(seconds))"
        }
        return "\(minutes):\(TimeTextPolicy.twoDigits(seconds))"
    }
}

public struct DurationParts: Equatable, Sendable {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
}
