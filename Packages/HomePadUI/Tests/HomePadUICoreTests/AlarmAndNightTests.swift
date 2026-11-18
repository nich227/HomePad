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

    @Test func alarmTimeDraft_whenCreated_thenStartsOnTheNextFiveMinuteStep() {
        let exact = AlarmTimeDraft(hour: 7, minute: 0)
        #expect(exact.hour == 7 && exact.minute == 0)
        let rounded = AlarmTimeDraft(hour: 7, minute: 31)
        #expect(rounded.hour == 7 && rounded.minute == 35)
        let nextHour = AlarmTimeDraft(hour: 9, minute: 58)
        #expect(nextHour.hour == 10 && nextHour.minute == 0)
        let nextDay = AlarmTimeDraft(hour: 23, minute: 57)
        #expect(nextDay.hour == 0 && nextDay.minute == 0)
    }

    @Test func alarmTimeDraft_whenStepped_thenHourAndMinuteWrapOnTheirOwn() {
        var draft = AlarmTimeDraft(hour: 23, minute: 55)
        draft.stepHour(by: 1)
        #expect(draft.hour == 0)
        draft.stepHour(by: -1)
        #expect(draft.hour == 23)
        draft.stepMinute(by: 1)
        #expect(draft.hour == 23 && draft.minute == 0)
        draft.stepMinute(by: -1)
        #expect(draft.hour == 23 && draft.minute == 55)
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

    private func appearance(_ schedule: NightSchedule, hour: Int, ambient: AmbientLightHint? = nil, override: NightOverride? = nil) -> NightAppearance {
        NightModePolicy.appearance(schedule: schedule, now: Fixtures.date(hour: hour), calendar: Fixtures.utc, ambient: ambient, override: override)
    }

    @Test func appearance_whenInsideWindow_thenNight() {
        #expect(appearance(NightSchedule(isEnabled: true), hour: 23) == .night(brightness: NightModePolicy.dimBrightness))
        #expect(appearance(NightSchedule(isEnabled: true), hour: 12) == .day)
        #expect(appearance(NightSchedule(isEnabled: false), hour: 23) == .day)
        #expect(NightAppearance.night(brightness: 0.1).isNight && !NightAppearance.day.isNight)
    }

    @Test func override_whenSwitchedByHand_thenDecidesUntilTheNextStartOrEndHour() {
        let schedule = NightSchedule(isEnabled: true)
        let evening = Fixtures.date(hour: 23)
        let off = NightModePolicy.toggled(from: .night(brightness: 0.06), schedule: schedule, now: evening, calendar: Fixtures.utc)
        #expect(off == NightOverride(isNight: false, expires: Fixtures.date(day: 2, hour: 7, minute: 0)))
        #expect(appearance(schedule, hour: 23, override: off) == .day)
        let afternoon = Fixtures.date(hour: 15)
        let on = NightModePolicy.toggled(from: .day, schedule: NightSchedule(isEnabled: false), now: afternoon, calendar: Fixtures.utc)
        #expect(on == NightOverride(isNight: true, expires: Fixtures.date(hour: 22, minute: 0)))
        #expect(appearance(NightSchedule(isEnabled: false), hour: 15, override: on) == .night(brightness: NightModePolicy.dimBrightness))
        // Past its end the override no longer counts and the schedule decides again.
        #expect(appearance(schedule, hour: 23, override: NightOverride(isNight: false, expires: Fixtures.date(hour: 22))) != .day)
        #expect(NightModePolicy.active(nil, now: evening) == nil)
        #expect(NightModePolicy.active(off, now: evening) == off)
        #expect(NightModePolicy.active(off, now: Fixtures.date(day: 2, hour: 7, minute: 0)) == nil)
    }

    @Test func override_whenAskedForByName_thenOnlyAChangeMakesOne() {
        let schedule = NightSchedule(isEnabled: true)
        let evening = Fixtures.date(hour: 23)
        let night = NightAppearance.night(brightness: NightModePolicy.dimBrightness)
        let kept = NightOverride(isNight: true, expires: evening.addingTimeInterval(60))
        #expect(NightModePolicy.override(setting: true, from: night, existing: nil, schedule: schedule, now: evening, calendar: Fixtures.utc) == nil)
        #expect(NightModePolicy.override(setting: true, from: night, existing: kept, schedule: schedule, now: evening, calendar: Fixtures.utc) == kept)
        let off = NightModePolicy.override(setting: false, from: night, existing: kept, schedule: schedule, now: evening, calendar: Fixtures.utc)
        #expect(off == NightOverride(isNight: false, expires: Fixtures.date(day: 2, hour: 7, minute: 0)))
        let on = NightModePolicy.override(setting: true, from: .day, existing: nil, schedule: schedule, now: Fixtures.date(hour: 15), calendar: Fixtures.utc)
        #expect(on == NightOverride(isNight: true, expires: Fixtures.date(hour: 22, minute: 0)))
        #expect(NightModePolicy.override(setting: false, from: .day, existing: nil, schedule: schedule, now: evening, calendar: Fixtures.utc) == nil)
    }

    @Test func override_whenScheduleHasNoHours_thenLastsHalfADay() {
        let empty = NightSchedule(isEnabled: true, startHour: 5, endHour: 5)
        let now = Fixtures.date()
        #expect(empty.nextHourBoundary(after: now, calendar: Fixtures.utc) == nil)
        let override = NightModePolicy.toggled(from: .day, schedule: empty, now: now, calendar: Fixtures.utc)
        #expect(override.expires == now.addingTimeInterval(NightModePolicy.fallbackOverrideDuration))
        #expect(NightSchedule(isEnabled: false).nextHourBoundary(after: Fixtures.date(hour: 23), calendar: Fixtures.utc) == Fixtures.date(day: 2, hour: 7, minute: 0))
    }

    @Test func quietTime_whenSwitchedOn_thenLastsUntilTheMorningAndSwitchesOff() {
        let schedule = NightSchedule(isEnabled: false)
        let now = Fixtures.date(hour: 20)
        let quiet = QuietTime.toggled(from: nil, schedule: schedule, now: now, calendar: Fixtures.utc)
        #expect(quiet == QuietTime(expires: Fixtures.date(day: 2, hour: 7, minute: 0)))
        #expect(quiet?.isActive(at: now) == true)
        #expect(quiet?.isActive(at: Fixtures.date(day: 2, hour: 7, minute: 0)) == false)
        #expect(QuietTime.toggled(from: quiet, schedule: schedule, now: now, calendar: Fixtures.utc) == nil)
        // One that already ran out is switched on again, not off.
        let stale = QuietTime(expires: now.addingTimeInterval(-1))
        #expect(QuietTime.toggled(from: stale, schedule: schedule, now: now, calendar: Fixtures.utc) == quiet)
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
