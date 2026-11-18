import Foundation

/// Day numbers match `Calendar`'s weekday component.
public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (first: Weekday, second: Weekday) -> Bool {
        first.rawValue < second.rawValue
    }
}

public struct HubAlarm: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var hour: Int
    public var minute: Int
    public var label: String
    /// Empty means the alarm fires once and then turns itself off.
    public var repeatDays: Set<Weekday>
    public var isEnabled: Bool

    public init(id: UUID = UUID(), hour: Int, minute: Int, label: String = "", repeatDays: Set<Weekday> = [], isEnabled: Bool = true) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
    }
}

public enum AlarmError: Error, Equatable, Sendable {
    case invalidTime(hour: Int, minute: Int)
    case unknownAlarm(UUID)
    case limitReached(Int)
}

/// The hub's alarms. Shared by the household, like a bedside clock.
public struct AlarmBook: Equatable, Sendable {
    public static let limit = 20
    public private(set) var alarms: [HubAlarm]

    public init(alarms: [HubAlarm] = []) {
        self.alarms = alarms
    }

    @discardableResult
    public mutating func add(hour: Int, minute: Int, label: String = "", repeatDays: Set<Weekday> = [], id: UUID = UUID()) throws(AlarmError) -> HubAlarm {
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw .invalidTime(hour: hour, minute: minute) }
        guard alarms.count < Self.limit else { throw .limitReached(Self.limit) }
        let alarm = HubAlarm(id: id, hour: hour, minute: minute, label: label.trimmingCharacters(in: .whitespacesAndNewlines), repeatDays: repeatDays)
        alarms.append(alarm)
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        return alarm
    }

    public mutating func setEnabled(_ enabled: Bool, id: UUID) throws(AlarmError) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { throw .unknownAlarm(id) }
        alarms[index].isEnabled = enabled
    }

    public mutating func remove(_ id: UUID) throws(AlarmError) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { throw .unknownAlarm(id) }
        alarms.remove(at: index)
    }

    /// Call after an alarm rang. A one-time alarm turns off; a repeating one stays on.
    public mutating func markFired(_ id: UUID) throws(AlarmError) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { throw .unknownAlarm(id) }
        if alarms[index].repeatDays.isEmpty {
            alarms[index].isEnabled = false
        }
    }
}

public enum AlarmSchedule {
    public static let snoozeMinutes = 9

    /// The next time the alarm rings strictly after `date`, or nil when it is off.
    public static func nextFireDate(for alarm: HubAlarm, after date: Date, calendar: Calendar) -> Date? {
        guard alarm.isEnabled else { return nil }
        var components = DateComponents()
        components.hour = alarm.hour
        components.minute = alarm.minute
        components.second = 0
        if alarm.repeatDays.isEmpty {
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
        return alarm.repeatDays.compactMap { day -> Date? in
            var dayComponents = components
            dayComponents.weekday = day.rawValue
            return calendar.nextDate(after: date, matching: dayComponents, matchingPolicy: .nextTime)
        }.min()
    }

    public static func nextAlarm(in alarms: [HubAlarm], after date: Date, calendar: Calendar) -> (alarm: HubAlarm, date: Date)? {
        alarms.compactMap { alarm -> (alarm: HubAlarm, date: Date)? in
            nextFireDate(for: alarm, after: date, calendar: calendar).map { (alarm, $0) }
        }.min { $0.date < $1.date }
    }

    /// Alarms whose ring time falls in `(lastCheck, now]`. The caller keeps `lastCheck` so an alarm
    /// rings once even when checks are irregular.
    public static func dueAlarms(in alarms: [HubAlarm], after lastCheck: Date, upTo now: Date, calendar: Calendar) -> [HubAlarm] {
        guard lastCheck < now else { return [] }
        return alarms.filter { alarm in
            guard let fire = nextFireDate(for: alarm, after: lastCheck, calendar: calendar) else { return false }
            return fire <= now
        }
    }

    public static func snoozeDate(from date: Date, minutes: Int = snoozeMinutes) -> Date {
        date.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }
}

public enum AlarmCodec {
    public static let version = 1
    private static let codec = VersionedCodec<[HubAlarm]>(version: version)

    public static func encode(_ alarms: [HubAlarm]) throws -> Data {
        try codec.encode(alarms)
    }

    public static func decode(_ data: Data) throws(SnapshotCodecError) -> [HubAlarm] {
        try codec.decode(data)
    }
}
