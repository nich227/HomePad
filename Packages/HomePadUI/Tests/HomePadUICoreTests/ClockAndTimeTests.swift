import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct ClockMathTests {
    @Test func handAngles_whenTenNine_thenHandsPointWhereAWatchWould() {
        let angles = ClockHandAngles(reading: ClockReading(hour: 10, minute: 9, second: 30))
        #expect(abs(angles.second - 180) < 0.0001)
        #expect(abs(angles.minute - 57) < 0.0001)
        #expect(abs(angles.hour - 304.75) < 0.0001)
    }

    @Test func handAngles_whenAfternoon_thenHourWrapsToTwelveHourDial() {
        let morning = ClockHandAngles(reading: ClockReading(hour: 3, minute: 0))
        let afternoon = ClockHandAngles(reading: ClockReading(hour: 15, minute: 0))
        #expect(morning.hour == 90)
        #expect(afternoon.hour == 90)
    }

    @Test func handAngles_whenNotSweeping_thenSecondHandIgnoresFraction() {
        let reading = ClockReading(hour: 0, minute: 0, second: 10, nanosecond: 500_000_000)
        #expect(ClockHandAngles(reading: reading, sweeps: false).second == 60)
        #expect(ClockHandAngles(reading: reading, sweeps: true).second == 63)
    }

    @Test func reading_whenOutOfRange_thenClamps() {
        let reading = ClockReading(hour: 99, minute: -4, second: 75, nanosecond: -1)
        #expect(reading == ClockReading(hour: 23, minute: 0, second: 59, nanosecond: 0))
    }

    @Test func reading_whenBuiltFromDate_thenUsesCalendarTimeZone() {
        let reading = ClockReading(date: Fixtures.date(hour: 22, minute: 41, second: 7), calendar: Fixtures.utc)
        #expect(reading.hour == 22)
        #expect(reading.minute == 41)
        #expect(reading.second == 7)
        #expect(reading.fractionalSecond == 7)
    }

    @Test func tickAngle_whenSixtyTicks_thenSixDegreesApart() {
        #expect(ClockDial.tickAngle(index: 15, count: 60) == 90)
        #expect(ClockDial.tickAngle(index: 3, count: 0) == 0)
    }

    @Test func isHourTick_whenEveryFifthOfSixty_thenTrue() {
        #expect(ClockDial.isHourTick(index: 0))
        #expect(ClockDial.isHourTick(index: 55))
        #expect(!ClockDial.isHourTick(index: 7))
        #expect(!ClockDial.isHourTick(index: 0, count: 0))
        #expect(!ClockDial.isHourTick(index: 0, count: 50))
    }

    @Test func numeralAngle_whenTwelve_thenZero() {
        #expect(ClockDial.numeralAngle(hour: 12) == 0)
        #expect(ClockDial.numeralAngle(hour: 3) == 90)
        #expect(ClockDial.numeralAngle(hour: -3) == 270)
    }

    @Test func point_whenQuarterTurns_thenLandsOnEdges() {
        let top = ClockDial.point(angle: 0, radius: 1)
        let right = ClockDial.point(angle: 90, radius: 1)
        let bottom = ClockDial.point(angle: 180, radius: 0.5)
        #expect(abs(top.x - 0.5) < 1e-9 && abs(top.y - 0) < 1e-9)
        #expect(abs(right.x - 1) < 1e-9 && abs(right.y - 0.5) < 1e-9)
        #expect(abs(bottom.x - 0.5) < 1e-9 && abs(bottom.y - 0.75) < 1e-9)
        #expect(DialPoint(x: 1, y: 2) == DialPoint(x: 1, y: 2))
    }

    @Test func angularDistance_whenAcrossZero_thenTakesShortWay() {
        #expect(ClockDial.angularDistance(350, 10) == 20)
        #expect(ClockDial.angularDistance(10, 100) == 90)
    }

    @Test func fadeOpacity_whenNumeralIsUnderMinuteHand_thenFullAndFadesWithDistance() {
        #expect(ClockDial.fadeOpacity(numeralHour: 2, minuteAngle: 60) == 1)
        let near = ClockDial.fadeOpacity(numeralHour: 3, minuteAngle: 60)
        let far = ClockDial.fadeOpacity(numeralHour: 5, minuteAngle: 60)
        #expect(near > far && far > 0)
        #expect(ClockDial.fadeOpacity(numeralHour: 8, minuteAngle: 60) == 0)
        #expect(ClockDial.fadeOpacity(numeralHour: 2, minuteAngle: 60, spread: 0) == 0)
    }
}

@Suite struct TimeTextTests {
    @Test func density_whenFarAndAdaptive_thenGlanceable() {
        #expect(FaceDensity(proximity: .far) == .glanceable)
        #expect(FaceDensity(proximity: .mid) == .contextual)
        #expect(FaceDensity(proximity: .near) == .detailed)
        #expect(FaceDensity(proximity: .far, adaptiveDetail: false) == .detailed)
        #expect(FaceDensity(proximity: .mid, adaptiveDetail: false) == .detailed)
    }

    @Test func density_whenCloser_thenLabelsThenControlsAppear() {
        #expect(FaceDensity.allCases.map(\.showsLabels) == [false, true, true])
        #expect(FaceDensity.allCases.map(\.showsControls) == [false, false, true])
        let middle = TimeTextPolicy.clockText(for: ClockReading(hour: 15, minute: 4, second: 9), density: .contextual, hourCycle: .twelve, showsSeconds: true)
        #expect(middle.secondText == "09" && middle.periodText == "PM")
        #expect(TimeTextPolicy.dateLineStyle(for: .contextual) == .full)
    }

    @Test func tokens_whenScaled_thenProportionalToTheShorterSide() {
        #expect(DesignTokens.scaled(DesignTokens.outerMargin, side: DesignTokens.baseSide) == 16)
        #expect(DesignTokens.scaled(DesignTokens.tileRadius, side: 1088) == 56)
        #expect(DesignTokens.hero(for: .glanceable) == DesignTokens.heroFar)
        #expect(DesignTokens.hero(for: .contextual) == DesignTokens.heroNear)
        #expect(DesignTokens.hero(for: .detailed) == DesignTokens.heroNear)
        #expect(DesignTokens.minimumTouch == 44 && DesignTokens.appIcon == 76 && DesignTokens.gutter == 12)
        #expect(DesignTokens.screenRadius == 60 && DesignTokens.tileTitle == 17 && DesignTokens.tileSubtitle == 14)
        #expect(DesignTokens.subtitleOpacity == 0.72 && DesignTokens.iconBadge == 36)
        #expect(DesignTokens.pillWidth == 260 && DesignTokens.pillHeight == 44)
        #expect(DesignTokens.pillCardWidth == 512 && DesignTokens.pillCardHeight == 220)
    }

    @Test func clockText_whenTwelveHourDetailed_thenShowsPeriodAndSeconds() {
        let text = TimeTextPolicy.clockText(for: ClockReading(hour: 15, minute: 4, second: 9), density: .detailed, hourCycle: .twelve, showsSeconds: true)
        #expect(text.digits == "3:04")
        #expect(text.periodText == "PM")
        #expect(text.secondText == "09")
    }

    @Test func clockText_whenGlanceable_thenDropsPeriodAndSeconds() {
        let text = TimeTextPolicy.clockText(for: ClockReading(hour: 9, minute: 30, second: 12), density: .glanceable, hourCycle: .twelve, showsSeconds: true)
        #expect(text == ClockText(hourText: "9", minuteText: "30", secondText: nil, periodText: nil))
    }

    @Test func clockText_whenMidnightAndNoon_thenTwelveNotZero() {
        let midnight = TimeTextPolicy.clockText(for: ClockReading(hour: 0, minute: 0), density: .detailed, hourCycle: .twelve)
        let noon = TimeTextPolicy.clockText(for: ClockReading(hour: 12, minute: 0), density: .detailed, hourCycle: .twelve)
        #expect(midnight.hourText == "12" && midnight.periodText == "AM")
        #expect(noon.hourText == "12" && noon.periodText == "PM")
        #expect(midnight.secondText == nil)
    }

    @Test func clockText_whenTwentyFourHour_thenZeroPadsAndHasNoPeriod() {
        let text = TimeTextPolicy.clockText(for: ClockReading(hour: 7, minute: 5), density: .detailed, hourCycle: .twentyFour)
        #expect(text.digits == "07:05")
        #expect(text.periodText == nil)
    }

    @Test func dateLine_whenShortAndFull_thenMatchesDensity() {
        #expect(TimeTextPolicy.dateLineStyle(for: .glanceable) == .short)
        #expect(TimeTextPolicy.dateLineStyle(for: .detailed) == .full)
        let locale = Locale(identifier: "en_US")
        let short = TimeTextPolicy.dateLine(for: Fixtures.date(), style: .short, calendar: Fixtures.utc, locale: locale)
        let full = TimeTextPolicy.dateLine(for: Fixtures.date(), style: .full, calendar: Fixtures.utc, locale: locale)
        #expect(short.contains("Wed") && short.contains("1") && !short.contains("April"))
        #expect(full.contains("Wednesday") && full.contains("April"))
    }

    @Test func refreshInterval_whenNoSeconds_thenOncePerMinute() {
        #expect(TimeTextPolicy.refreshInterval(showsSeconds: false, sweeps: false) == 60)
        #expect(TimeTextPolicy.refreshInterval(showsSeconds: true, sweeps: false) == 1)
        #expect(TimeTextPolicy.refreshInterval(showsSeconds: false, sweeps: true) < 0.1)
    }

    @Test func digitColumns_whenTenNine_thenFourDigits() {
        #expect(TimeTextPolicy.digitColumns(for: ClockReading(hour: 10, minute: 9), hourCycle: .twelve) == [1, 0, 0, 9])
        #expect(TimeTextPolicy.digitColumns(for: ClockReading(hour: 15, minute: 42), hourCycle: .twelve) == [0, 3, 4, 2])
        #expect(TimeTextPolicy.digitColumns(for: ClockReading(hour: 15, minute: 42), hourCycle: .twentyFour) == [1, 5, 4, 2])
    }

    @Test func greeting_whenHourChanges_thenDayPartFollows() {
        #expect(TimeTextPolicy.greeting(forHour: 6) == .morning)
        #expect(TimeTextPolicy.greeting(forHour: 13) == .afternoon)
        #expect(TimeTextPolicy.greeting(forHour: 19) == .evening)
        #expect(TimeTextPolicy.greeting(forHour: 2) == .night)
    }

    @Test func countdown_whenFractionRemains_thenRoundsUp() {
        #expect(DurationText.countdown(0.2) == "0:01")
        #expect(DurationText.countdown(245) == "4:05")
        #expect(DurationText.countdown(3845) == "1:04:05")
        #expect(DurationText.countdown(-3) == "0:00")
    }

    @Test func elapsed_whenFractionOrNotFinite_thenRoundsDown() {
        #expect(DurationText.elapsed(104.9) == "1:44")
        #expect(DurationText.elapsed(.nan) == "0:00")
    }

    @Test func compact_whenFifteenMinutes_thenSplitsParts() {
        #expect(DurationText.compact(900) == DurationParts(hours: 0, minutes: 15, seconds: 0))
        #expect(DurationText.compact(3725) == DurationParts(hours: 1, minutes: 2, seconds: 5))
    }
}
