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
        guard isEnabled else { return nil }
        return nextHourBoundary(after: date, calendar: calendar)
    }

    /// The next start or end hour, whether or not the schedule is on. A momentary override ends
    /// here, so it never outlives the evening or the morning it was set in.
    public func nextHourBoundary(after date: Date, calendar: Calendar) -> Date? {
        guard startHour != endHour else { return nil }
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
    /// Everything monochrome red on black. `brightness` is the screen brightness to ask for,
    /// 0...1.
    case night(brightness: Double)

    public var isNight: Bool { self != .day }
}

/// Night Mode switched by hand from the control center. It is held in memory only and ends at
/// the next start or end hour, so it is never a stored preference.
public struct NightOverride: Equatable, Sendable {
    public let isNight: Bool
    public let expires: Date

    public init(isNight: Bool, expires: Date) {
        self.isNight = isNight
        self.expires = expires
    }
}

public enum NightModePolicy {
    public static let darkBrightness = 0.02
    public static let dimBrightness = 0.06
    /// How long an override lasts when the schedule has no hours to end it at.
    public static let fallbackOverrideDuration: TimeInterval = 12 * 60 * 60

    /// An override in force decides. Otherwise the schedule does, adjusted by the room light when
    /// the schedule follows it.
    public static func appearance(
        schedule: NightSchedule,
        now: Date,
        calendar: Calendar,
        ambient: AmbientLightHint?,
        override: NightOverride? = nil
    ) -> NightAppearance {
        if let override = active(override, now: now) {
            return override.isNight ? .night(brightness: dimBrightness) : .day
        }
        guard schedule.isEnabled else { return .day }
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

    /// Night Mode asked for by name, from outside the control center: nothing changes when the
    /// hub is already that way, and otherwise it is the same as pressing the switch.
    public static func override(
        setting isNight: Bool,
        from current: NightAppearance,
        existing: NightOverride?,
        schedule: NightSchedule,
        now: Date,
        calendar: Calendar
    ) -> NightOverride? {
        guard current.isNight != isNight else { return existing }
        return toggled(from: current, schedule: schedule, now: now, calendar: calendar)
    }

    /// The override while it is still in force.
    public static func active(_ override: NightOverride?, now: Date) -> NightOverride? {
        guard let override, override.expires > now else { return nil }
        return override
    }

    /// What the control center's switch does: the opposite of what is showing, until the next
    /// start or end hour.
    public static func toggled(from current: NightAppearance, schedule: NightSchedule, now: Date, calendar: Calendar) -> NightOverride {
        let expires = schedule.nextHourBoundary(after: now, calendar: calendar) ?? now.addingTimeInterval(fallbackOverrideDuration)
        return NightOverride(isNight: !current.isNight, expires: expires)
    }
}

/// Do Not Disturb, switched from the control center. While it is on the hub shows no banners and
/// plays no timer or alarm sound. It is held in memory only and ends by itself the next morning.
public struct QuietTime: Equatable, Sendable {
    public let expires: Date

    public init(expires: Date) {
        self.expires = expires
    }

    public func isActive(at date: Date) -> Bool {
        expires > date
    }

    /// The switch: on until the next time the night schedule's end hour comes round, or off.
    public static func toggled(from current: QuietTime?, schedule: NightSchedule, now: Date, calendar: Calendar) -> QuietTime? {
        if let current, current.isActive(at: now) { return nil }
        let morning = calendar.nextDate(after: now, matching: DateComponents(hour: schedule.endHour, minute: 0, second: 0), matchingPolicy: .nextTime)
        return morning.map(QuietTime.init(expires:))
    }
}
