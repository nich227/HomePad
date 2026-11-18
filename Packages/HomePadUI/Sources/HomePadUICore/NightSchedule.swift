import Foundation

/// When the hub dims itself for the night. Hours are local wall-clock hours.
public struct NightSchedule: Equatable, Sendable {
    public var isEnabled: Bool
    public var startHour: Int
    public var endHour: Int
    /// When true, a lit room cancels night mode and a dark room starts it outside the window.
    public var followsRoomLight: Bool

    public init(isEnabled: Bool, startHour: Int = 22, endHour: Int = 7, followsRoomLight: Bool = false) {
        self.isEnabled = isEnabled
        self.startHour = ((startHour % 24) + 24) % 24
        self.endHour = ((endHour % 24) + 24) % 24
        self.followsRoomLight = followsRoomLight
    }

    /// The window may wrap past midnight. Equal start and end hours mean an empty window.
    public func contains(hour: Int) -> Bool {
        if startHour == endHour { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }

    public func isNight(at date: Date, calendar: Calendar) -> Bool {
        isEnabled && contains(hour: calendar.component(.hour, from: date))
    }

    /// The next moment the window opens or closes, for scheduling one re-evaluation.
    public func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        guard isEnabled, startHour != endHour else { return nil }
        return [startHour, endHour].compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min()
    }
}

/// How bright the room looks to whatever can estimate it, for example the camera's exposure.
public enum AmbientLightHint: String, Sendable {
    case dark, dim, bright
}

public enum NightAppearance: Equatable, Sendable {
    case day
    /// A dim red clock. `brightness` is the screen brightness to ask for, 0...1.
    case night(brightness: Double)
}

public enum NightModePolicy {
    public static let darkBrightness = 0.02
    public static let dimBrightness = 0.06
    /// How long a tap keeps the full interface up during the night.
    public static let wakeDuration: TimeInterval = 30

    /// A tap wakes the hub until `wakeUntil`. Otherwise the schedule decides, adjusted by the
    /// room light when the schedule follows it.
    public static func appearance(
        schedule: NightSchedule,
        now: Date,
        calendar: Calendar,
        ambient: AmbientLightHint?,
        wakeUntil: Date?
    ) -> NightAppearance {
        guard schedule.isEnabled else { return .day }
        if let wakeUntil, wakeUntil > now { return .day }
        let inWindow = schedule.isNight(at: now, calendar: calendar)
        let hint = schedule.followsRoomLight ? ambient : nil
        switch (inWindow, hint) {
        case (true, .bright): return .day
        case (true, .dark): return .night(brightness: darkBrightness)
        case (true, _): return .night(brightness: dimBrightness)
        case (false, .dark): return .night(brightness: darkBrightness)
        case (false, _): return .day
        }
    }

    public static func wakeDeadline(from now: Date) -> Date {
        now.addingTimeInterval(wakeDuration)
    }
}
