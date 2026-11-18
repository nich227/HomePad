import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@MainActor
@Suite struct SettingsTests {
    private func makeSettings() -> (HomePadSettings, UserDefaults, String) {
        let suite = "HomePadUICoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return (HomePadSettings(defaults: defaults, notificationCenter: NotificationCenter()), defaults, suite)
    }

    @Test func descriptors_whenListed_thenNamesAreUniqueAndPrefixed() {
        let names = UISettings.descriptors.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("ui.") })
        let panes = Set(UISettings.descriptors.map(\.pane))
        #expect(panes == ["Faces", "Display", "Night Mode", "Home Screen", "Weather"])
        #expect(UISettings.Faces.descriptors.count == FaceKind.allCases.count + 11)
    }

    @Test func descriptors_whenChoice_thenDefaultIsOneOfTheOptions() {
        for descriptor in UISettings.descriptors {
            guard case .choice(let options) = descriptor.control else { continue }
            let values = options.map(\.value)
            switch descriptor.defaultValue {
            case .string(let value): #expect(values.contains(value), "\(descriptor.name)")
            case .integer(let value): #expect(values.contains(String(value)), "\(descriptor.name)")
            default: Issue.record("choice \(descriptor.name) has a non-choice default")
            }
        }
        #expect(UISettings.Night.hourOptions.map(\.title).prefix(2) == ["12 AM", "1 AM"])
        #expect(UISettings.Night.hourOptions.last?.title == "11 PM")
        #expect(UISettings.Faces.title(for: .homeModular) == "Home Modular")
        #expect(Set(FaceKind.allCases.map(UISettings.Faces.title(for:))).count == FaceKind.allCases.count)
    }

    @Test func preferences_whenNothingSet_thenDefaultsMatchDescriptors() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.register(UISettings.descriptors)
        #expect(HubPreferences(settings: settings) == HubPreferences())
    }

    @Test func preferences_whenUserChangedValues_thenParsed() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "ui.face.flow.enabled")
        defaults.set("blue", forKey: "ui.face.digital.color")
        defaults.set("serif", forKey: "ui.face.digital.font")
        defaults.set(true, forKey: "ui.face.analog.ticks")
        defaults.set("all", forKey: "ui.face.analog.numerals")
        defaults.set("black", forKey: "ui.face.analog.color")
        defaults.set("rose", forKey: "ui.face.fade.color")
        defaults.set("sharedAlbum", forKey: "ui.face.photos.source")
        defaults.set("corner", forKey: "ui.face.photos.layout")
        defaults.set("Family", forKey: "ui.face.photos.albumName")
        defaults.set(15, forKey: "ui.face.photos.shuffleMinutes")
        defaults.set(false, forKey: "ui.face.flow.reactsToPresence")
        defaults.set("fill", forKey: "ui.display.canvas")
        defaults.set(false, forKey: "ui.display.adaptiveDetail")
        defaults.set(false, forKey: "ui.display.keepAwake")
        defaults.set("24", forKey: "ui.display.hourCycle")
        defaults.set("celsius", forKey: "ui.display.temperatureUnit")
        defaults.set(true, forKey: "ui.night.enabled")
        defaults.set(21, forKey: "ui.night.startHour")
        defaults.set(6, forKey: "ui.night.endHour")
        defaults.set(true, forKey: "ui.night.followsRoomLight")
        defaults.set(false, forKey: "ui.home.showsWidgets")
        defaults.set("black", forKey: "ui.home.wallpaper")
        defaults.set("Cupertino", forKey: "ui.weather.locationName")
        defaults.set("custom", forKey: "ui.weather.location")
        defaults.set(0, forKey: "ui.display.idleReturn")
        defaults.set("37.33", forKey: "ui.weather.latitude")
        defaults.set(" -122.03 ", forKey: "ui.weather.longitude")
        defaults.set(false, forKey: "general.setupMode")
        defaults.set("companion", forKey: "general.deviceRole")
        settings.refresh()
        let preferences = HubPreferences(settings: settings)
        #expect(!preferences.faces.enabledFaces.contains(.flow))
        #expect(preferences.faces.enabledFaces.count == FaceKind.allCases.count - 1)
        #expect(preferences.faces.digitalAccent == .blue)
        #expect(preferences.faces.digitalFont == .serif)
        #expect(preferences.faces.analogShowsTicks)
        #expect(preferences.faces.analogNumerals == .all)
        #expect(preferences.faces.analogColor == .black)
        #expect(preferences.faces.fadeColor == .rose)
        #expect(preferences.faces.photosSource == .sharedAlbum)
        #expect(preferences.faces.photosLayout == .corner)
        #expect(preferences.faces.photosAlbumName == "Family")
        #expect(preferences.faces.photosShuffleMinutes == 15)
        #expect(!preferences.faces.flowReactsToPresence)
        #expect(preferences.canvas == .fill)
        #expect(!preferences.adaptiveDetail)
        #expect(!preferences.keepAwake)
        #expect(preferences.hourCycle == .twentyFour)
        #expect(preferences.temperatureUnit == .celsius)
        #expect(preferences.night == NightSchedule(isEnabled: true, startHour: 21, endHour: 6, followsRoomLight: true))
        #expect(!preferences.homeShowsWidgets)
        #expect(preferences.homeWallpaper == .black)
        #expect(preferences.weatherSource == .custom)
        #expect(preferences.idleReturn == nil)
        #expect(preferences.weatherLocation?.name == "Cupertino")
        #expect(preferences.weatherLocation?.latitude == 37.33)
        #expect(preferences.weatherLocation?.longitude == -122.03)
        #expect(!preferences.setupMode)
        #expect(preferences.deviceRole == "companion")
    }

    @Test func preferences_whenStoredStringsAreUnknown_thenFallBackToDefaults() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in ["ui.face.digital.color", "ui.face.digital.font", "ui.face.analog.numerals", "ui.face.analog.color", "ui.face.fade.color", "ui.face.photos.source", "ui.face.photos.layout", "ui.display.canvas", "ui.display.hourCycle", "ui.display.temperatureUnit", "ui.home.wallpaper", "ui.weather.location"] {
            defaults.set("???", forKey: key)
        }
        settings.refresh()
        #expect(HubPreferences(settings: settings) == HubPreferences())
    }

    @Test func preferences_whenDefault_thenFillTheScreenAndReturnToFaceAfterTwoMinutes() {
        let preferences = HubPreferences()
        #expect(preferences.canvas == .fill)
        #expect(preferences.idleReturn == 120)
        #expect(preferences.weatherSource == .current)
        #expect(HubPreferences(idleReturn: 0).idleReturn == nil)
        #expect(HubPreferences(idleReturn: nil).idleReturn == nil)
        #expect(UISettings.Display.canvas.defaultValue == "fill")
        #expect(UISettings.Faces.title(for: .memories) == "Memories")
    }

    @Test func weatherPlace_whenResolved_thenThePlaceOrWhyThereIsNone() {
        let here = WeatherLocation(name: "Oslo", latitude: 59.9, longitude: 10.7)
        let typed = WeatherLocation(name: "Cupertino", latitude: 37.33, longitude: -122.03)
        #expect(WeatherPlace.resolve(source: .custom, custom: typed, permission: .denied, fix: here) == .ready(typed))
        #expect(WeatherPlace.resolve(source: .custom, custom: nil, permission: .allowed, fix: here) == .unavailable(.customLocationMissing))
        #expect(WeatherPlace.resolve(source: .current, custom: typed, permission: .notDetermined, fix: nil) == .unavailable(.needsLocationPermission))
        #expect(WeatherPlace.resolve(source: .current, custom: typed, permission: .denied, fix: here) == .unavailable(.locationDenied))
        #expect(WeatherPlace.resolve(source: .current, custom: typed, permission: .allowed, fix: nil) == .unavailable(.locating))
        #expect(WeatherPlace.resolve(source: .current, custom: typed, permission: .allowed, fix: here) == .ready(here))
        #expect(WeatherProblem.locationDenied.isFixedInSettings && WeatherProblem.customLocationMissing.isFixedInSettings)
        #expect(!WeatherProblem.locating.isFixedInSettings && !WeatherProblem.serviceUnavailable.isFixedInSettings)
        #expect(!WeatherProblem.needsLocationPermission.isFixedInSettings)
        #expect(WeatherLocationSource.allCases == [.current, .custom])
    }

    @Test func weatherLocation_whenCoordinatesMissingOrOffGlobe_thenNil() {
        #expect(WeatherLocation(name: "x", latitude: "", longitude: "") == nil)
        #expect(WeatherLocation(name: "x", latitude: "91", longitude: "0") == nil)
        #expect(WeatherLocation(name: "x", latitude: "0", longitude: "181") == nil)
        #expect(WeatherLocation(name: "x", latitude: "north", longitude: "3") == nil)
        #expect(WeatherLocation(name: " Oslo ", latitude: "59.9", longitude: "10.7")?.name == "Oslo")
    }

    @Test func unitSettings_whenAutomatic_thenFollowLocale() {
        #expect(HourCycleSetting.automatic.resolved(localeUses24Hour: true) == .twentyFour)
        #expect(HourCycleSetting.automatic.resolved(localeUses24Hour: false) == .twelve)
        #expect(HourCycleSetting.twelve.resolved(localeUses24Hour: true) == .twelve)
        #expect(HourCycleSetting.twentyFour.resolved(localeUses24Hour: false) == .twentyFour)
        #expect(TemperatureUnitSetting.automatic.resolved(localeUsesFahrenheit: true) == .fahrenheit)
        #expect(TemperatureUnitSetting.automatic.resolved(localeUsesFahrenheit: false) == .celsius)
        #expect(TemperatureUnitSetting.celsius.resolved(localeUsesFahrenheit: true) == .celsius)
        #expect(TemperatureUnitSetting.fahrenheit.resolved(localeUsesFahrenheit: false) == .fahrenheit)
    }
}
