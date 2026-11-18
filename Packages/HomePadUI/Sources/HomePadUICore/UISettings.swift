import Foundation
import HomePadCore

/// Preferences this package reads. They are edited in the system Settings app and never written
/// by the app. Face options are household-wide because a Settings bundle is static.
public enum UISettings {
    public enum Faces {
        public static let pane = "Faces"

        public static let digitalColor = SettingKey<String>("ui.face.digital.color", default: FaceAccent.white.rawValue)
        public static let digitalFont = SettingKey<String>("ui.face.digital.font", default: ClockFontStyle.rounded.rawValue)
        public static let analogTicks = SettingKey<Bool>("ui.face.analog.ticks", default: false)
        public static let analogNumerals = SettingKey<String>("ui.face.analog.numerals", default: AnalogNumeralStyle.large.rawValue)
        public static let analogColor = SettingKey<String>("ui.face.analog.color", default: AnalogDialColor.green.rawValue)
        public static let fadeColor = SettingKey<String>("ui.face.fade.color", default: FadeDialColor.gray.rawValue)
        public static let photosSource = SettingKey<String>("ui.face.photos.source", default: PhotosSource.picked.rawValue)
        public static let photosLayout = SettingKey<String>("ui.face.photos.layout", default: PhotosLayout.depth.rawValue)
        public static let photosAlbumName = SettingKey<String>("ui.face.photos.albumName", default: "")
        public static let photosShuffleMinutes = SettingKey<Int>("ui.face.photos.shuffleMinutes", default: 5)
        public static let flowReactsToPresence = SettingKey<Bool>("ui.face.flow.reactsToPresence", default: true)

        public static func enabled(_ face: FaceKind) -> SettingKey<Bool> {
            SettingKey<Bool>("ui.face.\(face.rawValue).enabled", default: true)
        }

        public static func title(for face: FaceKind) -> String {
            switch face {
            case .modular: "Modular"
            case .photos: "Photos"
            case .weather: "Weather"
            case .homeModular: "Home Modular"
            case .calendar: "Calendar"
            case .flow: "Flow"
            case .analog: "Analog"
            case .fade: "Fade"
            case .digital: "Digital"
            case .homeCamera: "Home Camera"
            case .rainbow: "Rainbow"
            }
        }

        static let accentOptions: [SettingDescriptor.Option] = [
            .init(title: "White", value: "white"),
            .init(title: "Match Profile", value: "profile"),
            .init(title: "Green", value: "green"),
            .init(title: "Yellow", value: "yellow"),
            .init(title: "Orange", value: "orange"),
            .init(title: "Red", value: "red"),
            .init(title: "Purple", value: "purple"),
            .init(title: "Blue", value: "blue"),
        ]

        public static let descriptors: [SettingDescriptor] = FaceKind.allCases.map { face in
            SettingDescriptor(
                enabled(face),
                title: title(for: face),
                pane: pane,
                footer: face == FaceKind.allCases.last ? "Swipe left or right on the hub to change faces. Each person's last face is remembered." : nil
            )
        } + [
            SettingDescriptor(digitalColor, title: "Digital Color", pane: pane, options: accentOptions),
            SettingDescriptor(digitalFont, title: "Digital Font", pane: pane, options: [
                .init(title: "Rounded", value: "rounded"),
                .init(title: "Standard", value: "standard"),
                .init(title: "Serif", value: "serif"),
                .init(title: "Monospaced", value: "monospaced"),
            ]),
            SettingDescriptor(analogTicks, title: "Analog Tick Marks", pane: pane),
            SettingDescriptor(analogNumerals, title: "Analog Numerals", pane: pane, options: [
                .init(title: "Large", value: "large"),
                .init(title: "All Twelve", value: "all"),
                .init(title: "None", value: "none"),
            ]),
            SettingDescriptor(analogColor, title: "Analog Color", pane: pane, options: [
                .init(title: "Green", value: "green"),
                .init(title: "Yellow", value: "yellow"),
                .init(title: "Orange", value: "orange"),
                .init(title: "Red", value: "red"),
                .init(title: "Purple", value: "purple"),
                .init(title: "Blue", value: "blue"),
                .init(title: "Black", value: "black"),
            ]),
            SettingDescriptor(fadeColor, title: "Fade Color", pane: pane, options: [
                .init(title: "Gray", value: "gray"),
                .init(title: "Rose", value: "rose"),
            ]),
            SettingDescriptor(photosSource, title: "Photos Source", pane: pane, options: [
                .init(title: "Photos Chosen in HomePad", value: "picked"),
                .init(title: "Shared Album", value: "sharedAlbum"),
            ]),
            SettingDescriptor(
                photosAlbumName,
                title: "Shared Album Name",
                pane: pane,
                footer: "Leave empty to use the first shared album."
            ),
            SettingDescriptor(photosLayout, title: "Photos Time Layout", pane: pane, options: [
                .init(title: "Behind the Subject", value: "depth"),
                .init(title: "In Front", value: "front"),
                .init(title: "Small, in the Corner", value: "corner"),
            ]),
            SettingDescriptor(photosShuffleMinutes, title: "Change Photo Every", pane: pane, options: [
                .init(title: "Minute", value: "1"),
                .init(title: "5 Minutes", value: "5"),
                .init(title: "15 Minutes", value: "15"),
                .init(title: "Hour", value: "60"),
            ]),
            SettingDescriptor(
                flowReactsToPresence,
                title: "Flow Reacts to Presence",
                pane: pane,
                footer: "The Flow face drifts toward whoever is in front of the screen."
            ),
        ]
    }

    public enum Display {
        public static let pane = "Display"

        public static let canvas = SettingKey<String>("ui.display.canvas", default: CanvasMode.square.rawValue)
        public static let adaptiveDetail = SettingKey<Bool>("ui.display.adaptiveDetail", default: true)
        public static let keepAwake = SettingKey<Bool>("ui.display.keepAwake", default: true)
        public static let hourCycle = SettingKey<String>("ui.display.hourCycle", default: "automatic")
        public static let temperatureUnit = SettingKey<String>("ui.display.temperatureUnit", default: "automatic")

        public static let descriptors: [SettingDescriptor] = [
            SettingDescriptor(
                canvas,
                title: "Screen Layout",
                pane: pane,
                options: [
                    .init(title: "Square (like HomeView)", value: "square"),
                    .init(title: "Fill the screen", value: "fill"),
                ],
                footer: "Square centers the face on black. Fill adds a second column beside it."
            ),
            SettingDescriptor(
                adaptiveDetail,
                title: "Adapt Detail to Distance",
                pane: pane,
                footer: "Shows larger, simpler faces from across the room and more detail up close."
            ),
            SettingDescriptor(keepAwake, title: "Keep Screen Awake", pane: pane),
            SettingDescriptor(hourCycle, title: "Time Format", pane: pane, options: [
                .init(title: "Automatic", value: "automatic"),
                .init(title: "12-Hour", value: "12"),
                .init(title: "24-Hour", value: "24"),
            ]),
            SettingDescriptor(temperatureUnit, title: "Temperature", pane: pane, options: [
                .init(title: "Automatic", value: "automatic"),
                .init(title: "Celsius", value: "celsius"),
                .init(title: "Fahrenheit", value: "fahrenheit"),
            ]),
        ]
    }

    public enum Night {
        public static let pane = "Night Mode"

        public static let enabled = SettingKey<Bool>("ui.night.enabled", default: false)
        public static let startHour = SettingKey<Int>("ui.night.startHour", default: 22)
        public static let endHour = SettingKey<Int>("ui.night.endHour", default: 7)
        public static let followsRoomLight = SettingKey<Bool>("ui.night.followsRoomLight", default: false)

        static let hourOptions: [SettingDescriptor.Option] = (0..<24).map { hour in
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            return .init(title: "\(twelve) \(hour < 12 ? "AM" : "PM")", value: String(hour))
        }

        public static let descriptors: [SettingDescriptor] = [
            SettingDescriptor(
                enabled,
                title: "Night Mode",
                pane: pane,
                footer: "Dims the hub to a red clock at night. Tap the screen to wake it for a moment."
            ),
            SettingDescriptor(startHour, title: "Starts At", pane: pane, options: hourOptions),
            SettingDescriptor(endHour, title: "Ends At", pane: pane, options: hourOptions),
            SettingDescriptor(
                followsRoomLight,
                title: "Follow Room Light",
                pane: pane,
                footer: "Stays bright while the room is lit and dims whenever the room is dark."
            ),
        ]
    }

    public enum HomeScreen {
        public static let pane = "Home Screen"

        public static let showsWidgets = SettingKey<Bool>("ui.home.showsWidgets", default: true)
        public static let wallpaper = SettingKey<String>("ui.home.wallpaper", default: HomeWallpaper.face.rawValue)

        public static let descriptors: [SettingDescriptor] = [
            SettingDescriptor(showsWidgets, title: "Show Widgets", pane: pane),
            SettingDescriptor(wallpaper, title: "Background", pane: pane, options: [
                .init(title: "Blurred Face", value: "face"),
                .init(title: "Black", value: "black"),
            ]),
        ]
    }

    public enum Weather {
        public static let pane = "Weather"

        public static let locationName = SettingKey<String>("ui.weather.locationName", default: "")
        public static let latitude = SettingKey<String>("ui.weather.latitude", default: "")
        public static let longitude = SettingKey<String>("ui.weather.longitude", default: "")

        public static let descriptors: [SettingDescriptor] = [
            SettingDescriptor(locationName, title: "City", pane: pane),
            SettingDescriptor(latitude, title: "Latitude", pane: pane),
            SettingDescriptor(
                longitude,
                title: "Longitude",
                pane: pane,
                footer: "HomePad does not use Location Services. Enter the hub's coordinates in decimal degrees to show weather."
            ),
        ]
    }

    public static let descriptors: [SettingDescriptor] =
        Faces.descriptors + Display.descriptors + Night.descriptors + HomeScreen.descriptors + Weather.descriptors
}

/// A place to show weather for, entered by hand in Settings.
public struct WeatherLocation: Equatable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double

    /// Nil unless both coordinates parse and are on the globe.
    public init?(name: String, latitude: String, longitude: String) {
        let trimmedLatitude = latitude.trimmingCharacters(in: .whitespaces)
        let trimmedLongitude = longitude.trimmingCharacters(in: .whitespaces)
        guard let lat = Double(trimmedLatitude), let lon = Double(trimmedLongitude),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = lat
        self.longitude = lon
    }
}

public enum HourCycleSetting: String, Sendable {
    case automatic
    case twelve = "12"
    case twentyFour = "24"

    public func resolved(localeUses24Hour: Bool) -> HourCycle {
        switch self {
        case .automatic: localeUses24Hour ? .twentyFour : .twelve
        case .twelve: .twelve
        case .twentyFour: .twentyFour
        }
    }
}

/// Every preference the shell reads, parsed into plain values. Unknown strings fall back to the
/// key's default so a stale or hand-edited value cannot break a face.
public struct HubPreferences: Equatable, Sendable {
    public var faces: FaceOptions
    public var canvas: CanvasMode
    public var adaptiveDetail: Bool
    public var keepAwake: Bool
    public var hourCycle: HourCycleSetting
    public var temperatureUnit: TemperatureUnitSetting
    public var night: NightSchedule
    public var homeShowsWidgets: Bool
    public var homeWallpaper: HomeWallpaper
    public var weatherLocation: WeatherLocation?
    public var setupMode: Bool
    public var deviceRole: String

    public init(
        faces: FaceOptions = FaceOptions(),
        canvas: CanvasMode = .square,
        adaptiveDetail: Bool = true,
        keepAwake: Bool = true,
        hourCycle: HourCycleSetting = .automatic,
        temperatureUnit: TemperatureUnitSetting = .automatic,
        night: NightSchedule = NightSchedule(isEnabled: false),
        homeShowsWidgets: Bool = true,
        homeWallpaper: HomeWallpaper = .face,
        weatherLocation: WeatherLocation? = nil,
        setupMode: Bool = true,
        deviceRole: String = "automatic"
    ) {
        self.faces = faces
        self.canvas = canvas
        self.adaptiveDetail = adaptiveDetail
        self.keepAwake = keepAwake
        self.hourCycle = hourCycle
        self.temperatureUnit = temperatureUnit
        self.night = night
        self.homeShowsWidgets = homeShowsWidgets
        self.homeWallpaper = homeWallpaper
        self.weatherLocation = weatherLocation
        self.setupMode = setupMode
        self.deviceRole = deviceRole
    }

    @MainActor
    public init(settings: HomePadSettings) {
        typealias Faces = UISettings.Faces
        typealias Display = UISettings.Display
        self.init(
            faces: FaceOptions(
                enabledFaces: FaceKind.allCases.filter { settings[Faces.enabled($0)] },
                digitalAccent: FaceAccent(rawValue: settings[Faces.digitalColor]) ?? .white,
                digitalFont: ClockFontStyle(rawValue: settings[Faces.digitalFont]) ?? .rounded,
                analogShowsTicks: settings[Faces.analogTicks],
                analogNumerals: AnalogNumeralStyle(rawValue: settings[Faces.analogNumerals]) ?? .large,
                analogColor: AnalogDialColor(rawValue: settings[Faces.analogColor]) ?? .green,
                fadeColor: FadeDialColor(rawValue: settings[Faces.fadeColor]) ?? .gray,
                photosSource: PhotosSource(rawValue: settings[Faces.photosSource]) ?? .picked,
                photosLayout: PhotosLayout(rawValue: settings[Faces.photosLayout]) ?? .depth,
                photosAlbumName: settings[Faces.photosAlbumName],
                photosShuffleMinutes: settings[Faces.photosShuffleMinutes],
                flowReactsToPresence: settings[Faces.flowReactsToPresence]
            ),
            canvas: CanvasMode(rawValue: settings[Display.canvas]) ?? .square,
            adaptiveDetail: settings[Display.adaptiveDetail],
            keepAwake: settings[Display.keepAwake],
            hourCycle: HourCycleSetting(rawValue: settings[Display.hourCycle]) ?? .automatic,
            temperatureUnit: TemperatureUnitSetting(rawValue: settings[Display.temperatureUnit]) ?? .automatic,
            night: NightSchedule(
                isEnabled: settings[UISettings.Night.enabled],
                startHour: settings[UISettings.Night.startHour],
                endHour: settings[UISettings.Night.endHour],
                followsRoomLight: settings[UISettings.Night.followsRoomLight]
            ),
            homeShowsWidgets: settings[UISettings.HomeScreen.showsWidgets],
            homeWallpaper: HomeWallpaper(rawValue: settings[UISettings.HomeScreen.wallpaper]) ?? .face,
            weatherLocation: WeatherLocation(
                name: settings[UISettings.Weather.locationName],
                latitude: settings[UISettings.Weather.latitude],
                longitude: settings[UISettings.Weather.longitude]
            ),
            setupMode: settings[GeneralSettings.setupMode],
            deviceRole: settings[GeneralSettings.deviceRole]
        )
    }
}
