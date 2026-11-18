import Foundation
import HomePadCore

/// How much a face shows. Glanceable is for someone across the room.
public enum FaceDensity: String, CaseIterable, Sendable {
    case glanceable
    case detailed

    /// With adaptive detail off the hub always shows the detailed layout.
    public init(proximity: Proximity, adaptiveDetail: Bool = true) {
        self = adaptiveDetail && proximity == .far ? .glanceable : .detailed
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
        let detailed = density == .detailed
        return ClockText(
            hourText: hourCycle == .twentyFour ? twoDigits(hour) : String(hour),
            minuteText: twoDigits(reading.minute),
            secondText: detailed && showsSeconds ? twoDigits(reading.second) : nil,
            periodText: detailed ? period : nil
        )
    }

    public static func dateLineStyle(for density: FaceDensity) -> DateLineStyle {
        density == .detailed ? .full : .short
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
