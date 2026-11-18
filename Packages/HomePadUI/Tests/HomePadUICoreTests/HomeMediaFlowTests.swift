import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct HomeModelTests {
    private var snapshot: HomeSnapshot {
        HomeSnapshot(
            homeName: "Home",
            accessories: [
                HomeAccessory(id: "a1", name: "Lights", roomName: "Entryway", kind: .light, isOn: true, brightness: 80),
                HomeAccessory(id: "a2", name: "Door Lock", roomName: "Front Door", kind: .lock, isOn: true),
                HomeAccessory(id: "a3", name: "Fan", roomName: "Office", kind: .fan, isOn: false, isReachable: false),
                HomeAccessory(id: "a4", name: "Lamp", roomName: "Entryway", kind: .light, isOn: false),
                HomeAccessory(id: "a5", name: "Outlet", roomName: "Office", kind: .outlet, isOn: false),
                HomeAccessory(id: "a6", name: "Switch", roomName: "Office", kind: .other, isOn: false),
            ],
            scenes: [HomeScene(id: "s1", name: "Good Morning"), HomeScene(id: "s2", name: "Good Night"), HomeScene(id: "s3", name: "Movie")],
            thermostats: [HomeThermostat(id: "t1", name: "Thermostat", roomName: "Living Room", currentCelsius: 20, targetCelsius: 20)],
            cameras: [HomeCamera(id: "c1", name: "Porch", roomName: "Front Door")]
        )
    }

    @Test func roomNames_whenAccessoriesShareRooms_thenFirstSeenOrderWithoutDuplicates() {
        #expect(snapshot.roomNames == ["Entryway", "Front Door", "Office"])
        #expect(snapshot.accessories(inRoom: "Entryway").map(\.id) == ["a1", "a4"])
        #expect(HomeSnapshot.empty.roomNames.isEmpty)
    }

    @Test func smallTiles_whenHomeHasEverything_thenCameraScenesThenReachableAccessories() {
        let tiles = HomeFavorites.smallTiles(in: snapshot)
        #expect(tiles.map(\.id) == ["camera.c1", "scene.s1", "scene.s2", "accessory.a1", "accessory.a2"])
        #expect(HomeFavorites.smallTiles(in: snapshot, limit: 0).isEmpty)
        let noCamera = HomeSnapshot(accessories: snapshot.accessories)
        #expect(HomeFavorites.smallTiles(in: noCamera).map(\.id) == ["accessory.a1", "accessory.a2", "accessory.a4", "accessory.a5", "accessory.a6"])
    }

    @Test func sceneSymbol_whenNameSuggestsTimeOfDay_thenMatchingGlyph() {
        #expect(HomeScene(id: "1", name: "Good Morning").symbolName == "sun.max.fill")
        #expect(HomeScene(id: "2", name: "Good Night").symbolName == "moon.fill")
        #expect(HomeScene(id: "3", name: "Arrive Home").symbolName == "figure.walk.arrival")
        #expect(HomeScene(id: "4", name: "Leave").symbolName == "figure.walk.departure")
        #expect(HomeScene(id: "5", name: "Movie").symbolName == "sparkles")
        #expect(Set(HomeAccessoryKind.allCases.map(\.symbolName)).count == HomeAccessoryKind.allCases.count)
    }

    @Test func mayOperate_whenGuestUnlocksDoor_thenRefused() {
        let lock = HomeAccessory(id: "l", name: "Door Lock", roomName: "Front Door", kind: .lock, isOn: true)
        let light = HomeAccessory(id: "a", name: "Lights", roomName: "Entryway", kind: .light, isOn: true)
        #expect(!HomeControlPolicy.mayOperate(lock, turningOn: false, isGuest: true))
        #expect(HomeControlPolicy.mayOperate(lock, turningOn: true, isGuest: true))
        #expect(HomeControlPolicy.mayOperate(lock, turningOn: false, isGuest: false))
        #expect(HomeControlPolicy.mayOperate(light, turningOn: false, isGuest: true))
    }

    @Test func stepped_whenFahrenheit_thenOneDisplayedDegree() {
        let up = ThermostatMath.stepped(targetCelsius: 20, direction: 1, unit: .fahrenheit)
        #expect(TemperatureUnit.fahrenheit.rounded(fromCelsius: up) == 69)
        #expect(ThermostatMath.stepped(targetCelsius: 20, direction: -1, unit: .celsius) == 19)
        #expect(ThermostatMath.stepped(targetCelsius: 32, direction: 5, unit: .celsius) == 32)
        #expect(ThermostatMath.stepped(targetCelsius: 10, direction: -1, unit: .celsius) == 10)
    }

    @Test func brightness_whenZeroOrOutOfRange_thenClampsAndTurnsOff() {
        #expect(BrightnessMath.normalized(0).isOn == false)
        #expect(BrightnessMath.normalized(55.4).brightness == 55)
        #expect(BrightnessMath.normalized(180).brightness == 100)
        #expect(BrightnessMath.normalized(.nan).brightness == 0)
    }

    @Test func cameraGrid_whenCountGrows_thenUpToThreeByThree() {
        let shapes = (0...12).map { CameraGrid.dimensions(count: $0) }.map { [$0.columns, $0.rows] }
        #expect(shapes == [[1, 1], [1, 1], [2, 1], [2, 2], [2, 2], [3, 2], [3, 2], [3, 3], [3, 3], [3, 3], [3, 3], [3, 3], [3, 3]])
    }
}

@Suite struct MediaAndWeatherTests {
    @Test func nowPlaying_whenHalfway_thenProgressAndRemaining() {
        let playing = NowPlaying(title: "Song", artist: "Artist", isPlaying: true, duration: 207, elapsed: 104)
        #expect(abs(playing.progress - 104.0 / 207.0) < 1e-9)
        #expect(playing.remaining == 103)
        let unknown = NowPlaying(title: "Live", isPlaying: true, duration: 0, elapsed: .nan)
        #expect(unknown.progress == 0)
        #expect(unknown.remaining == 0)
        #expect(NowPlaying(title: "x", isPlaying: false, duration: 10, elapsed: 50).progress == 1)
    }

    @Test func temperatureUnit_whenFahrenheit_thenConverts() {
        #expect(TemperatureUnit.fahrenheit.value(fromCelsius: 20) == 68)
        #expect(TemperatureUnit.celsius.value(fromCelsius: 20) == 20)
        #expect(TemperatureUnit.fahrenheit.rounded(fromCelsius: 12.2) == 54)
    }

    @Test func weather_whenOlderThanTwoHours_thenStale() async throws {
        let snapshot = WeatherSnapshot(locationName: "San Francisco", temperatureCelsius: 12, highCelsius: 14, lowCelsius: 9, conditionText: "Partly Cloudy", symbolName: "cloud.sun.fill", humidity: 0.76, windKilometersPerHour: 11, sunset: Fixtures.date(hour: 19), asOf: Fixtures.date())
        #expect(!snapshot.isStale(at: Fixtures.date(hour: 11)))
        #expect(snapshot.isStale(at: Fixtures.date(hour: 13)))
        #expect(try await FixedWeatherProvider(snapshot: snapshot).currentWeather() == snapshot)
        await #expect(throws: WeatherError.notConfigured) { try await PlaceholderWeatherProvider().currentWeather() }
    }
}

@Suite struct FlowFieldTests {
    @Test func facePosition_whenOutOfRangeOrNotFinite_thenClampedOrCentered() {
        #expect(FacePosition(x: 2, y: -1) == FacePosition(x: 1, y: 0))
        #expect(FacePosition(x: .nan, y: .infinity) == .center)
    }

    @Test func parameters_whenNobodyThere_thenCenteredWithNoPull() {
        let parameters = FlowField.parameters(position: nil, time: 6, proximity: .far, reduceMotion: false)
        #expect(parameters.focus == FlowPoint(x: 0.5, y: 0.5))
        #expect(parameters.pull == 0)
        #expect(abs(parameters.phase - .pi / 2) < 1e-9)
        #expect(parameters.amplitude == 0.05)
        #expect(parameters.scale == 1)
    }

    @Test func parameters_whenViewerNear_thenFocusFollowsAndPullGrows() {
        let near = FlowField.parameters(position: FacePosition(x: 0.8, y: 0.2), time: 0, proximity: .near, reduceMotion: false)
        let far = FlowField.parameters(position: FacePosition(x: 0.8, y: 0.2), time: 0, proximity: .far, reduceMotion: false)
        #expect(near.focus == FlowPoint(x: 0.8, y: 0.2))
        #expect(near.pull > far.pull && far.pull > 0)
        #expect(near.scale > far.scale)
        #expect(near.amplitude < far.amplitude)
    }

    @Test func parameters_whenReduceMotion_thenFrozen() {
        let parameters = FlowField.parameters(position: FacePosition(x: 0.1, y: 0.9), time: 11, proximity: .near, reduceMotion: true)
        #expect(parameters.phase == 0)
        #expect(parameters.amplitude == 0)
        #expect(parameters.pull > 0)
    }

    @Test func displaced_whenFocusMovesRight_thenShapeLeansRight() {
        let rest = FlowPoint(x: 0.5, y: 0.5)
        let still = FlowParameters(focus: FlowPoint(x: 0.5, y: 0.5), phase: 0, amplitude: 0, pull: 0.5, scale: 1)
        let leaning = FlowParameters(focus: FlowPoint(x: 1, y: 0), phase: 0, amplitude: 0, pull: 0.5, scale: 1)
        #expect(FlowField.displaced(rest: rest, index: 0, count: 4, parameters: still) == rest)
        let moved = FlowField.displaced(rest: rest, index: 0, count: 4, parameters: leaning)
        #expect(moved.x > rest.x && moved.y < rest.y)
        let wobbling = FlowParameters(focus: FlowPoint(x: 0.5, y: 0.5), phase: 0, amplitude: 0.1, pull: 0, scale: 1)
        #expect(abs(FlowField.displaced(rest: rest, index: 0, count: 0, parameters: wobbling).x - 0.6) < 1e-9)
    }

    @Test func meshPoints_whenAnimated_thenCornersStayAndEdgesSlideAlongEdges() {
        let parameters = FlowField.parameters(position: FacePosition(x: 0.9, y: 0.9), time: 5, proximity: .near, reduceMotion: false)
        let points = FlowField.meshPoints(columns: 3, rows: 3, parameters: parameters)
        #expect(points.count == 9)
        #expect(points[0] == FlowPoint(x: 0, y: 0))
        #expect(points[8] == FlowPoint(x: 1, y: 1))
        #expect(points[1].y == 0 && points[1].x != 0.5)
        #expect(points[3].x == 0 && points[3].y != 0.5)
        #expect(points[4] != FlowPoint(x: 0.5, y: 0.5))
        #expect(FlowField.meshPoints(columns: 1, rows: 3, parameters: parameters).isEmpty)
    }

    @Test func smoother_whenTargetAppears_thenEasesTowardItAndBackToCenter() {
        var smoother = FlowFocusSmoother()
        let first = smoother.advance(toward: FacePosition(x: 1, y: 1), deltaTime: 0.1)
        #expect(first.x > 0.5 && first.x < 1)
        smoother.advance(toward: FacePosition(x: 1, y: 1), deltaTime: 10)
        #expect(abs(smoother.current.x - 1) < 1e-6)
        smoother.advance(toward: nil, deltaTime: 10)
        #expect(abs(smoother.current.x - 0.5) < 1e-6)
        let before = smoother.current
        smoother.advance(toward: FacePosition(x: 0, y: 0), deltaTime: .nan)
        smoother.advance(toward: FacePosition(x: 0, y: 0), deltaTime: -1)
        #expect(smoother.current == before)
        #expect(FlowFocusSmoother(responsiveness: -4).responsiveness == 0)
    }
}

@Suite struct CalendarGridTests {
    @Test func grid_whenApril2026_thenStartsOnPreviousSundayAndMarksToday() {
        let grid = CalendarGrid(containing: Fixtures.date(), calendar: Fixtures.utc)
        #expect(grid.days.count == 42)
        #expect(grid.monthStart == Fixtures.date(hour: 0, minute: 0))
        #expect(grid.days.prefix(4).map(\.number) == [29, 30, 31, 1])
        #expect(grid.days.prefix(3).allSatisfy { !$0.isInMonth })
        #expect(grid.days[3].isInMonth && grid.days[3].isToday)
        #expect(grid.days.filter(\.isToday).count == 1)
        #expect(grid.days.filter(\.isInMonth).count == 30)
        #expect(grid.weeks.count == 6 && grid.weeks.allSatisfy { $0.count == 7 })
        #expect(grid.weekdayOrder == [1, 2, 3, 4, 5, 6, 7])
        #expect(grid.days[3].id == grid.days[3].date)
    }

    @Test func grid_whenWeekStartsOnMonday_thenColumnsShift() {
        var calendar = Fixtures.utc
        calendar.firstWeekday = 2
        let grid = CalendarGrid(containing: Fixtures.date(), calendar: calendar)
        #expect(grid.weekdayOrder == [2, 3, 4, 5, 6, 7, 1])
        #expect(grid.days.prefix(3).map(\.number) == [30, 31, 1])
    }
}
