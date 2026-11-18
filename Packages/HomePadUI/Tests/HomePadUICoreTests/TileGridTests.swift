import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct TileGridTests {
    @Test func grid_whenChosenFromTheSpace_thenWideTallSquareAndSmall() {
        #expect(TileGrid(width: 1306, height: 900) == TileGrid(columns: 4, rows: 3))
        #expect(TileGrid(width: 964, height: 1242) == TileGrid(columns: 3, rows: 4))
        #expect(TileGrid(width: 600, height: 600) == TileGrid(columns: 3, rows: 3))
        #expect(TileGrid(width: 370, height: 700) == TileGrid(columns: 2, rows: 4))
        #expect(TileGrid(width: 700, height: 300) == TileGrid(columns: 4, rows: 2))
        #expect(TileGrid(width: 300, height: 300) == TileGrid(columns: 2, rows: 2))
    }

    @Test func grid_whenNothingFits_thenTheCoarsestAndNeverEmpty() {
        #expect(TileGrid(width: 200, height: 200) == TileGrid(columns: 2, rows: 2))
        #expect(TileGrid(width: 0, height: 0) == TileGrid(columns: 2, rows: 2))
        #expect(TileGrid(columns: 0, rows: -3) == TileGrid(columns: 1, rows: 1))
        #expect(TileGrid(columns: 4, rows: 3).cellCount == 12)
    }

    @Test func placementFrame_whenSpanningCells_thenIncludesTheGapsBetweenThem() {
        let grid = TileGrid(columns: 4, rows: 3)
        let single = TilePlacement(column: 1, row: 2).frame(in: grid, width: 436, height: 324, gap: 12)
        #expect(single == CanvasFrame(x: 112, y: 224, width: 100, height: 100))
        let large = TilePlacement(column: 0, row: 0, columnSpan: 2, rowSpan: 2).frame(in: grid, width: 436, height: 324, gap: 12)
        #expect(large == CanvasFrame(x: 0, y: 0, width: 212, height: 212))
    }

    @Test func pack_whenTilesAreMixed_thenFirstFreeSpotReadingAcrossThenDown() {
        let grid = TileGrid(columns: 3, rows: 3)
        let placed = TileGridPacker.pack([.large, .single, .single, .init(columns: 3, rows: 1), .single], in: grid)
        #expect(placed == [
            TilePlacement(column: 0, row: 0, columnSpan: 2, rowSpan: 2),
            TilePlacement(column: 2, row: 0),
            TilePlacement(column: 2, row: 1),
            TilePlacement(column: 0, row: 2, columnSpan: 3, rowSpan: 1),
            nil,
        ])
    }

    @Test func pack_whenATileIsLargerThanTheGrid_thenItTakesOneCell() {
        let placed = TileGridPacker.pack([.init(columns: 5, rows: 1), .large], in: TileGrid(columns: 2, rows: 2))
        #expect(placed == [TilePlacement(column: 0, row: 0), nil])
        #expect(TileGridPacker.Span.single == TileGridPacker.Span(columns: 1, rows: 1))
    }

    @Test func homeModular_whenPacked_thenHeroClockAndAsManyTilesAsFit() {
        let wide = HomeModularLayout.placements(in: TileGrid(columns: 4, rows: 3), tileCount: 20)
        #expect(wide.count == 9)
        #expect(wide[0] == .init(slot: .hero, placement: TilePlacement(column: 0, row: 0, columnSpan: 2, rowSpan: 2)))
        #expect(wide[1] == .init(slot: .clock, placement: TilePlacement(column: 2, row: 0)))
        #expect(wide[2] == .init(slot: .tile(0), placement: TilePlacement(column: 3, row: 0)))
        #expect(wide.last == .init(slot: .tile(6), placement: TilePlacement(column: 3, row: 2)))
        let few = HomeModularLayout.placements(in: TileGrid(columns: 3, rows: 3), tileCount: 2)
        #expect(few.map(\.slot) == [.hero, .clock, .tile(0), .tile(1)])
        let none = HomeModularLayout.placements(in: TileGrid(columns: 2, rows: 2), tileCount: -1)
        #expect(none.map(\.slot) == [.hero])
    }

    @Test func modular_whenWideTallOrSquare_thenThreeByTwoTwoByThreeOrTwoByTwo() {
        #expect(ModularLayout.grid(width: 1300, height: 900) == TileGrid(columns: 3, rows: 2))
        #expect(ModularLayout.grid(width: 900, height: 1300) == TileGrid(columns: 2, rows: 3))
        #expect(ModularLayout.grid(width: 600, height: 600) == TileGrid(columns: 2, rows: 2))
        #expect(ModularLayout.grid(width: 0, height: 10) == TileGrid(columns: 2, rows: 2))
        #expect(ModularLayout.widgets(for: TileGrid(columns: 2, rows: 2)) == [.date, .clock, .weather, .nowPlaying])
        #expect(ModularLayout.widgets(for: TileGrid(columns: 3, rows: 2)) == ModularLayout.Widget.allCases)
    }

    @Test func homeScreenGrid_whenWider_thenMoreColumnsAndWidgetsWithinLimits() {
        #expect(HomeScreenGrid.columns(width: 600, unit: 6) == 4)
        #expect(HomeScreenGrid.columns(width: 1366, unit: 10.24) == 5)
        #expect(HomeScreenGrid.columns(width: 1133, unit: 7.44) == 6)
        #expect(HomeScreenGrid.columns(width: 2000, unit: 5) == 8)
        #expect(HomeScreenGrid.columns(width: 600, unit: 0) == 4)
        #expect(HomeScreenGrid.widgetCount(width: 600, unit: 6) == 3)
        #expect(HomeScreenGrid.widgetCount(width: 1366, unit: 10.24) == 4)
        #expect(HomeScreenGrid.widgetCount(width: 2000, unit: 5) == 6)
        #expect(HomeScreenGrid.widgetCount(width: 100, unit: 6) == 2)
        #expect(HomeScreenGrid.widgetCount(width: 600, unit: 0) == 2)
    }
}

@Suite struct LivePillTests {
    private let guest = AudienceContext(isGuest: true, isPersonalContentUnlocked: false, setupMode: false)
    private let manual = AudienceContext(isGuest: false, isPersonalContentUnlocked: false, setupMode: false)
    private let unlocked = AudienceContext(isGuest: false, isPersonalContentUnlocked: true, setupMode: false)

    private func strip(_ names: [String]) -> TimerStrip {
        let clock = TestClock()
        var engine = TimerEngine(clock: { clock.now })
        for name in names {
            _ = try? engine.add(name: name, duration: 300)
        }
        return TimerStrip(engine: engine, limit: 3)
    }

    private let note = LivePillItem(id: "note", kind: .note, symbolName: "note.text", title: "Dinner at 7", isPersonal: true)
    private let page = LivePillItem(id: "page", kind: .page, symbolName: "safari", title: "Recipe")

    @Test func items_whenEverythingIsLive_thenConfirmationTimersMusicThenExtras() {
        let playing = NowPlaying(title: "Song", artist: "Band", isPlaying: true)
        let items = LivePill.items(recognizedName: "Erica", timers: strip(["Pasta"]), nowPlaying: playing, extras: [note, page], context: unlocked)
        #expect(items.map(\.kind) == [.recognized, .timer, .nowPlaying, .note])
        #expect(items[0].title == "Erica" && items[0].app == nil)
        #expect(items[1].title == "5:00" && items[1].detail == "Pasta" && items[1].app == .timers)
        #expect(items[2].title == "Song" && items[2].detail == "Band" && items[2].app == .music)
        #expect(items[3].app == .intercom && page.app == .beam)
        // A note opens Intercom only while a package is supplying it.
        #expect(items[3].destination(available: []) == nil)
        #expect(items[3].destination(available: [.intercom]) == .intercom)
        #expect(items[1].destination(available: []) == .timers)
        #expect(items[0].destination(available: [.intercom]) == nil)
        #expect(items.count == LivePill.limit)
    }

    @Test func items_whenGuestOrLocked_thenNothingPersonal() {
        let paused = NowPlaying(title: "Song", isPlaying: false)
        let forGuest = LivePill.items(recognizedName: "Erica", timers: strip([]), nowPlaying: paused, extras: [note, page], context: guest)
        #expect(forGuest == [page])
        let locked = LivePill.items(timers: strip([]), nowPlaying: nil, extras: [note, page], context: manual)
        #expect(locked == [page])
        #expect(LivePill.items(timers: strip([]), nowPlaying: nil, extras: [], context: unlocked).isEmpty)
        #expect(LivePill.recognitionSeconds == 4)
    }
}

@Suite struct DialAndDimmerTests {
    @Test func angle_whenTargetSet_thenAcrossThreeQuartersOfACircle() {
        #expect(ThermostatDial.angle(forCelsius: 10) == -135)
        #expect(ThermostatDial.angle(forCelsius: 21) == 0)
        #expect(ThermostatDial.angle(forCelsius: 32) == 135)
        #expect(ThermostatDial.angle(forCelsius: 50) == 135)
        #expect(ThermostatDial.angle(forCelsius: -5) == -135)
    }

    @Test func celsius_whenTouched_thenWholeDegreesInTheUnitShownAndTheGapGoesToTheNearerEnd() {
        #expect(ThermostatDial.celsius(forOffsetX: 0, y: -1, unit: .celsius) == 21)
        #expect(ThermostatDial.celsius(forOffsetX: 1, y: 0, unit: .celsius) == 28)
        #expect(ThermostatDial.celsius(forOffsetX: -1, y: 0, unit: .celsius) == 14)
        #expect(ThermostatDial.celsius(forOffsetX: 0.01, y: 1, unit: .celsius) == 32)
        #expect(ThermostatDial.celsius(forOffsetX: -0.01, y: 1, unit: .celsius) == 10)
        #expect(abs(ThermostatDial.celsius(forOffsetX: 0, y: -1, unit: .fahrenheit) - 190.0 / 9) < 1e-9)
        #expect(ThermostatDial.celsius(forOffsetX: 1, y: 1, unit: .fahrenheit) == 32)
        #expect(ThermostatDial.celsius(forOffsetX: -1, y: 1, unit: .fahrenheit) == 10)
    }

    @Test func brightness_whenTouchedOnTheTrack_thenFullAtTheTopAndClamped() {
        #expect(DimmerMath.brightness(forY: 0, height: 320) == 100)
        #expect(DimmerMath.brightness(forY: 80, height: 320) == 75)
        #expect(DimmerMath.brightness(forY: 320, height: 320) == 0)
        #expect(DimmerMath.brightness(forY: -40, height: 320) == 100)
        #expect(DimmerMath.brightness(forY: 900, height: 320) == 0)
        #expect(DimmerMath.brightness(forY: 10, height: 0) == 0)
        #expect(DimmerMath.temperatureSwatches == DimmerMath.temperatureSwatches.sorted(by: >))
    }
}

@Suite struct MemoriesAndSkyTests {
    @Test func frame_whenNoPhotos_thenNil() {
        #expect(MemoriesSlideshow.frame(count: 0, at: Date(timeIntervalSinceReferenceDate: 5)) == nil)
    }

    @Test func frame_whenTimePasses_thenPhotosTakeTurnsAndFadeAtTheEnd() throws {
        let start = try #require(MemoriesSlideshow.frame(count: 3, at: Date(timeIntervalSinceReferenceDate: 0)))
        #expect(start.index == 0 && start.progress == 0 && start.opacity == 1)
        #expect(abs(start.scale - 1.06) < 1e-9)
        #expect(abs(start.offsetX + 0.03) < 1e-9 && abs(start.offsetY + 0.03) < 1e-9)
        let middle = try #require(MemoriesSlideshow.frame(count: 3, at: Date(timeIntervalSinceReferenceDate: 18)))
        #expect(middle.index == 1 && middle.progress == 0.5)
        #expect(abs(middle.scale - 1.1) < 1e-9)
        #expect(abs(middle.offsetX) < 1e-9)
        let fading = try #require(MemoriesSlideshow.frame(count: 3, at: Date(timeIntervalSinceReferenceDate: 11.25)))
        #expect(fading.index == 0 && abs(fading.opacity - 0.5) < 1e-9)
        let wrapped = try #require(MemoriesSlideshow.frame(count: 3, at: Date(timeIntervalSinceReferenceDate: 36)))
        #expect(wrapped.index == 0)
        let before = try #require(MemoriesSlideshow.frame(count: 3, at: Date(timeIntervalSinceReferenceDate: -6)))
        #expect(before.index == 2)
    }

    @Test func frame_whenOnePhotoOrReduceMotion_thenNoFadeOrNoDrift() throws {
        let only = try #require(MemoriesSlideshow.frame(count: 1, at: Date(timeIntervalSinceReferenceDate: 11.9)))
        #expect(only.opacity == 1)
        let still = try #require(MemoriesSlideshow.frame(count: 2, at: Date(timeIntervalSinceReferenceDate: 18), reduceMotion: true))
        #expect(still.scale == 1 && still.offsetX == 0 && still.offsetY == 0 && still.index == 1)
    }

    @Test func sky_whenReadFromTheConditionSymbol_thenTheMatchingKind() {
        #expect(SkyKind(symbolName: "sun.max.fill") == .clear)
        #expect(SkyKind(symbolName: nil) == .clear)
        #expect(SkyKind(symbolName: "cloud.sun.fill") == .cloudy)
        #expect(SkyKind(symbolName: "cloud.rain.fill") == .rain)
        #expect(SkyKind(symbolName: "cloud.drizzle") == .rain)
        #expect(SkyKind(symbolName: "cloud.bolt.rain.fill") == .storm)
        #expect(SkyKind(symbolName: "cloud.snow") == .snow)
        #expect(SkyKind(symbolName: "cloud.sleet") == .snow)
        #expect(SkyKind(symbolName: "cloud.hail") == .snow)
        #expect(SkyKind(symbolName: "cloud.fog") == .fog)
        #expect(SkyKind(symbolName: "sun.haze") == .fog)
        #expect(SkyKind(symbolName: "smoke.fill") == .fog)
        #expect(SkyKind(symbolName: "moon.stars.fill") == .night)
        #expect(SkyKind.allCases.filter(\.hasPrecipitation) == [.rain, .snow, .storm])
    }

    @Test func precipitationChance_whenOutOfRange_thenClamped() {
        func snapshot(_ chance: Double?) -> WeatherSnapshot {
            WeatherSnapshot(locationName: "x", temperatureCelsius: 1, highCelsius: 2, lowCelsius: 0, conditionText: "", symbolName: "sun.max", precipitationChance: chance, asOf: Fixtures.date())
        }
        #expect(snapshot(nil).precipitationChance == nil)
        #expect(snapshot(0.3).precipitationChance == 0.3)
        #expect(snapshot(1.7).precipitationChance == 1)
        #expect(snapshot(-2).precipitationChance == 0)
    }

    @Test func quantities_whenAStepHasAmounts_thenEachIsFound() {
        func found(_ text: String) -> [String] {
            RecipeQuantities.ranges(in: text).map { String(text[$0]) }
        }
        #expect(found("Add 2 cups flour and 1/2 tsp salt.") == ["2 cups", "1/2 tsp"])
        #expect(found("Bake at 350°F for 25-30 minutes.") == ["350°F", "25-30 minutes"])
        #expect(found("Simmer 1 1/2 hours, then add ½ cup cream and 3 eggs.") == ["1 1/2 hours", "½ cup", "3"])
        #expect(found("Use 200 g butter, 1.5 l stock.") == ["200 g", "1.5 l"])
        #expect(found("Stir gently until glossy.").isEmpty)
        #expect(found("Step2 is version v1.2").isEmpty)
    }
}
