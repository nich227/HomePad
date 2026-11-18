import Foundation
import Testing
@testable import HomePadUICore

@Suite struct AlarmTests {
    @Test func add_whenTimeValid_thenSortedByTimeOfDay() throws {
        var book = AlarmBook()
        try book.add(hour: 9, minute: 30, label: " Gym ")
        try book.add(hour: 6, minute: 45)
        try book.add(hour: 9, minute: 0)
        #expect(book.alarms.map { [$0.hour, $0.minute] } == [[6, 45], [9, 0], [9, 30]])
        #expect(book.alarms[2].label == "Gym")
        #expect(Weekday.monday < Weekday.friday)
    }

    @Test func add_whenTimeInvalidOrFull_thenThrows() throws {
        var book = AlarmBook()
        #expect(throws: AlarmError.invalidTime(hour: 24, minute: 0)) { try book.add(hour: 24, minute: 0) }
        #expect(throws: AlarmError.invalidTime(hour: 3, minute: 60)) { try book.add(hour: 3, minute: 60) }
        for index in 0..<AlarmBook.limit {
            try book.add(hour: index, minute: 0)
        }
        #expect(throws: AlarmError.limitReached(AlarmBook.limit)) { try book.add(hour: 1, minute: 1) }
    }

    @Test func editing_whenAlarmUnknown_thenThrows() {
        var book = AlarmBook()
        let missing = UUID()
        #expect(throws: AlarmError.unknownAlarm(missing)) { try book.setEnabled(false, id: missing) }
        #expect(throws: AlarmError.unknownAlarm(missing)) { try book.remove(missing) }
        #expect(throws: AlarmError.unknownAlarm(missing)) { try book.markFired(missing) }
    }

    @Test func markFired_whenOneTime_thenTurnsOffButRepeatingStaysOn() throws {
        var book = AlarmBook()
        let once = try book.add(hour: 7, minute: 0)
        let weekdays = try book.add(hour: 8, minute: 0, repeatDays: [.monday, .tuesday])
        try book.markFired(once.id)
        try book.markFired(weekdays.id)
        #expect(book.alarms.first { $0.id == once.id }?.isEnabled == false)
        #expect(book.alarms.first { $0.id == weekdays.id }?.isEnabled == true)
        try book.setEnabled(true, id: once.id)
        #expect(book.alarms.first { $0.id == once.id }?.isEnabled == true)
        try book.remove(once.id)
        #expect(book.alarms.count == 1)
    }

    @Test func nextFireDate_whenOneTimeAlarmAlreadyPassedToday_thenTomorrow() {
        let alarm = HubAlarm(hour: 7, minute: 0)
        let next = AlarmSchedule.nextFireDate(for: alarm, after: Fixtures.date(hour: 10), calendar: Fixtures.utc)
        #expect(next == Fixtures.date(day: 2, hour: 7, minute: 0))
        let later = HubAlarm(hour: 22, minute: 15)
        #expect(AlarmSchedule.nextFireDate(for: later, after: Fixtures.date(hour: 10), calendar: Fixtures.utc) == Fixtures.date(hour: 22, minute: 15))
    }

    @Test func nextFireDate_whenRepeating_thenPicksNearestChosenDay() {
        // April 1, 2026 is a Wednesday.
        let alarm = HubAlarm(hour: 7, minute: 0, repeatDays: [.monday, .friday])
        let next = AlarmSchedule.nextFireDate(for: alarm, after: Fixtures.date(hour: 10), calendar: Fixtures.utc)
        #expect(next == Fixtures.date(day: 3, hour: 7, minute: 0))
    }

    @Test func nextFireDate_whenDisabled_thenNil() {
        let alarm = HubAlarm(hour: 7, minute: 0, isEnabled: false)
        #expect(AlarmSchedule.nextFireDate(for: alarm, after: Fixtures.date(), calendar: Fixtures.utc) == nil)
    }

    @Test func nextAlarm_whenSeveral_thenSoonest() {
        let alarms = [HubAlarm(hour: 23, minute: 0), HubAlarm(hour: 12, minute: 0, label: "Lunch"), HubAlarm(hour: 1, minute: 0, isEnabled: false)]
        let next = AlarmSchedule.nextAlarm(in: alarms, after: Fixtures.date(hour: 10), calendar: Fixtures.utc)
        #expect(next?.alarm.label == "Lunch")
        #expect(next?.date == Fixtures.date(hour: 12, minute: 0))
        #expect(AlarmSchedule.nextAlarm(in: [], after: Fixtures.date(), calendar: Fixtures.utc) == nil)
    }

    @Test func dueAlarms_whenRingTimeInsideWindow_thenRingsExactlyOnce() {
        let alarm = HubAlarm(hour: 10, minute: 10)
        let before = Fixtures.date(hour: 10, minute: 9, second: 30)
        let after = Fixtures.date(hour: 10, minute: 10, second: 5)
        #expect(AlarmSchedule.dueAlarms(in: [alarm], after: before, upTo: after, calendar: Fixtures.utc) == [alarm])
        #expect(AlarmSchedule.dueAlarms(in: [alarm], after: after, upTo: after.addingTimeInterval(30), calendar: Fixtures.utc).isEmpty)
        #expect(AlarmSchedule.dueAlarms(in: [alarm], after: after, upTo: before, calendar: Fixtures.utc).isEmpty)
        let off = HubAlarm(hour: 10, minute: 10, isEnabled: false)
        #expect(AlarmSchedule.dueAlarms(in: [off], after: before, upTo: after, calendar: Fixtures.utc).isEmpty)
    }

    @Test func snoozeDate_whenDefault_thenNineMinutes() {
        let now = Fixtures.date()
        #expect(AlarmSchedule.snoozeDate(from: now) == now.addingTimeInterval(540))
        #expect(AlarmSchedule.snoozeDate(from: now, minutes: 0) == now.addingTimeInterval(60))
    }

    @Test func codec_whenRoundTripped_thenAlarmsSurvive() throws {
        let alarms = [HubAlarm(hour: 6, minute: 30, label: "Up", repeatDays: [.saturday, .sunday])]
        #expect(try AlarmCodec.decode(AlarmCodec.encode(alarms)) == alarms)
        #expect(throws: SnapshotCodecError.corrupt) { try AlarmCodec.decode(Data()) }
    }
}

@Suite struct NightScheduleTests {
    @Test func contains_whenWindowWrapsMidnight_thenLateAndEarlyHoursAreNight() {
        let schedule = NightSchedule(isEnabled: true, startHour: 22, endHour: 7)
        #expect(schedule.contains(hour: 23))
        #expect(schedule.contains(hour: 3))
        #expect(!schedule.contains(hour: 7))
        #expect(!schedule.contains(hour: 12))
    }

    @Test func contains_whenWindowInsideOneDay_thenOnlyBetween() {
        let schedule = NightSchedule(isEnabled: true, startHour: 1, endHour: 5)
        #expect(schedule.contains(hour: 1))
        #expect(!schedule.contains(hour: 5))
        #expect(!schedule.contains(hour: 23))
    }

    @Test func contains_whenStartEqualsEnd_thenNever() {
        let schedule = NightSchedule(isEnabled: true, startHour: 8, endHour: 8)
        #expect(!schedule.contains(hour: 8))
        #expect(schedule.nextBoundary(after: Fixtures.date(), calendar: Fixtures.utc) == nil)
    }

    @Test func init_whenHoursOutOfRange_thenWraps() {
        let schedule = NightSchedule(isEnabled: true, startHour: 46, endHour: -17)
        #expect(schedule.startHour == 22)
        #expect(schedule.endHour == 7)
    }

    @Test func isNight_whenDisabled_thenFalseEvenInsideWindow() {
        let night = Fixtures.date(hour: 23)
        #expect(NightSchedule(isEnabled: true).isNight(at: night, calendar: Fixtures.utc))
        #expect(!NightSchedule(isEnabled: false).isNight(at: night, calendar: Fixtures.utc))
    }

    @Test func nextBoundary_whenDaytime_thenTonightsStart() {
        let schedule = NightSchedule(isEnabled: true)
        #expect(schedule.nextBoundary(after: Fixtures.date(hour: 10), calendar: Fixtures.utc) == Fixtures.date(hour: 22, minute: 0))
        #expect(schedule.nextBoundary(after: Fixtures.date(hour: 23), calendar: Fixtures.utc) == Fixtures.date(day: 2, hour: 7, minute: 0))
        #expect(NightSchedule(isEnabled: false).nextBoundary(after: Fixtures.date(), calendar: Fixtures.utc) == nil)
    }

    private func appearance(_ schedule: NightSchedule, hour: Int, ambient: AmbientLightHint? = nil, wakeUntil: Date? = nil) -> NightAppearance {
        NightModePolicy.appearance(schedule: schedule, now: Fixtures.date(hour: hour), calendar: Fixtures.utc, ambient: ambient, wakeUntil: wakeUntil)
    }

    @Test func appearance_whenInsideWindow_thenDimRedClock() {
        #expect(appearance(NightSchedule(isEnabled: true), hour: 23) == .night(brightness: NightModePolicy.dimBrightness))
        #expect(appearance(NightSchedule(isEnabled: true), hour: 12) == .day)
        #expect(appearance(NightSchedule(isEnabled: false), hour: 23) == .day)
    }

    @Test func appearance_whenTappedAwake_thenDayUntilDeadline() {
        let schedule = NightSchedule(isEnabled: true)
        let now = Fixtures.date(hour: 23)
        let deadline = NightModePolicy.wakeDeadline(from: now)
        #expect(deadline == now.addingTimeInterval(30))
        #expect(appearance(schedule, hour: 23, wakeUntil: deadline) == .day)
        #expect(appearance(schedule, hour: 23, wakeUntil: now.addingTimeInterval(-1)) != .day)
    }

    @Test func appearance_whenFollowingRoomLight_thenLitRoomCancelsAndDarkRoomStarts() {
        let follows = NightSchedule(isEnabled: true, followsRoomLight: true)
        #expect(appearance(follows, hour: 23, ambient: .bright) == .day)
        #expect(appearance(follows, hour: 23, ambient: .dark) == .night(brightness: NightModePolicy.darkBrightness))
        #expect(appearance(follows, hour: 23, ambient: .dim) == .night(brightness: NightModePolicy.dimBrightness))
        #expect(appearance(follows, hour: 12, ambient: .dark) == .night(brightness: NightModePolicy.darkBrightness))
        #expect(appearance(follows, hour: 12, ambient: .dim) == .day)
        let ignores = NightSchedule(isEnabled: true, followsRoomLight: false)
        #expect(appearance(ignores, hour: 23, ambient: .bright) == .night(brightness: NightModePolicy.dimBrightness))
        #expect(appearance(ignores, hour: 12, ambient: .dark) == .day)
    }
}
