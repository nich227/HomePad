import Foundation

/// Wall-clock fields of one instant in one calendar.
public struct ClockReading: Equatable, Sendable {
    public let hour: Int
    public let minute: Int
    public let second: Int
    public let nanosecond: Int

    public init(hour: Int, minute: Int, second: Int = 0, nanosecond: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.second = min(max(second, 0), 59)
        self.nanosecond = min(max(nanosecond, 0), 999_999_999)
    }

    public init(date: Date, calendar: Calendar) {
        self.init(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date),
            second: calendar.component(.second, from: date),
            nanosecond: calendar.component(.nanosecond, from: date)
        )
    }

    public var fractionalSecond: Double {
        Double(second) + Double(nanosecond) / 1_000_000_000
    }
}

/// Hand rotations in degrees, clockwise from twelve.
public struct ClockHandAngles: Equatable, Sendable {
    public let hour: Double
    public let minute: Double
    public let second: Double

    /// `sweeps` moves the second hand continuously; otherwise it ticks once per second.
    public init(reading: ClockReading, sweeps: Bool = true) {
        let seconds = sweeps ? reading.fractionalSecond : Double(reading.second)
        let minutes = Double(reading.minute) + seconds / 60
        let hours = Double(reading.hour % 12) + minutes / 60
        second = seconds * 6
        minute = minutes * 6
        hour = hours * 30
    }
}

public struct DialPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum ClockDial {
    /// Degrees clockwise from twelve for tick `index` of `count` evenly spaced ticks.
    public static func tickAngle(index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(index) * 360 / Double(count)
    }

    /// With sixty ticks, every fifth one marks an hour.
    public static func isHourTick(index: Int, count: Int = 60) -> Bool {
        guard count > 0, count % 12 == 0 else { return false }
        return index % (count / 12) == 0
    }

    /// Degrees clockwise from twelve for an hour numeral, where twelve is zero.
    public static func numeralAngle(hour: Int) -> Double {
        Double(((hour % 12) + 12) % 12) * 30
    }

    /// A point in the unit square (origin top leading, center at 0.5) at `angle` degrees clockwise
    /// from twelve and `radius` as a fraction of half the square's side.
    public static func point(angle: Double, radius: Double) -> DialPoint {
        let radians = angle * .pi / 180
        return DialPoint(x: 0.5 + sin(radians) * radius / 2, y: 0.5 - cos(radians) * radius / 2)
    }

    /// Smallest rotation between two dial angles, in 0...180.
    public static func angularDistance(_ first: Double, _ second: Double) -> Double {
        let raw = abs(first - second).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }

    /// How visible a Fade face numeral is: full next to the minute hand, gone on the far side.
    public static func fadeOpacity(numeralHour: Int, minuteAngle: Double, spread: Double = 110) -> Double {
        guard spread > 0 else { return 0 }
        let distance = angularDistance(numeralAngle(hour: numeralHour), minuteAngle)
        let falloff = max(0, 1 - distance / spread)
        return falloff * falloff
    }
}
