import Foundation
import HomePadCore
import HomePadUICore
import Observation
import UIKit

/// The services the shell draws from. Create one for the app's lifetime with `live()`, or build
/// one from preview services.
@MainActor
@Observable
public final class HubEnvironment {
    public let layoutStore: any LayoutStore
    public let timers: TimerCenter
    public let alarms: AlarmCenter
    public let home: any HomeService
    public let music: any MusicService
    public let camera: any CameraPreviewService
    public let weather: WeatherCenter
    public let photos: FacePhotoLibrary
    public let recipes: RecipeLibrary

    public init(
        layoutStore: any LayoutStore,
        timers: TimerCenter,
        alarms: AlarmCenter,
        home: any HomeService,
        music: any MusicService,
        camera: any CameraPreviewService,
        weather: WeatherCenter,
        photos: FacePhotoLibrary,
        recipes: RecipeLibrary
    ) {
        self.layoutStore = layoutStore
        self.timers = timers
        self.alarms = alarms
        self.home = home
        self.music = music
        self.camera = camera
        self.weather = weather
        self.photos = photos
        self.recipes = recipes
    }

    /// Real services, with state under `Application Support/HomePad/UI`. Falls back to memory
    /// when that directory cannot be resolved, so the hub still starts.
    public static func live() -> HubEnvironment {
        let base = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HomePad", isDirectory: true)
            .appendingPathComponent("UI", isDirectory: true)
        func store(_ name: String) -> any SnapshotStore {
            guard let base else { return InMemorySnapshotStore() }
            return FileSnapshotStore(url: base.appendingPathComponent(name))
        }
        let sound = SystemAlertSound()
        let layouts: any LayoutStore = base.map { FileLayoutStore(directory: $0.appendingPathComponent("Layouts", isDirectory: true)) } ?? InMemoryLayoutStore()
        return HubEnvironment(
            layoutStore: layouts,
            timers: TimerCenter(store: store("timers.json"), sound: sound),
            alarms: AlarmCenter(store: store("alarms.json"), sound: sound),
            home: HomeKitHomeService(),
            music: SystemMusicService(),
            camera: FrontCameraPreviewService(),
            weather: .live(),
            photos: FacePhotoLibrary(directory: base?.appendingPathComponent("FacePhotos", isDirectory: true)),
            recipes: RecipeLibrary()
        )
    }

    /// In-memory services with sample content. Touches no hardware, files, or network.
    public static func preview(runningTimer: Bool = true) -> HubEnvironment {
        let timers = TimerCenter()
        if runningTimer {
            timers.add(name: String(localized: "Pasta"), duration: 15 * 60)
        }
        let weather = WeatherCenter(provider: FixedWeatherProvider(snapshot: WeatherSnapshot(
            locationName: "San Francisco",
            temperatureCelsius: 12.2,
            highCelsius: 13.9,
            lowCelsius: 9.4,
            conditionText: String(localized: "Partly Cloudy"),
            symbolName: "cloud.sun.fill",
            humidity: 0.76,
            windKilometersPerHour: 11,
            sunset: Date().addingTimeInterval(4 * 3600),
            asOf: Date()
        )))
        weather.configure(location: nil)
        return HubEnvironment(
            layoutStore: InMemoryLayoutStore(),
            timers: timers,
            alarms: AlarmCenter(),
            home: PreviewHomeService(),
            music: PreviewMusicService(),
            camera: PreviewCameraService(),
            weather: weather,
            photos: FacePhotoLibrary(directory: nil),
            recipes: RecipeLibrary(loader: FixedRecipePageLoader(html: nil))
        )
    }
}

/// The system ends an app that asks for a protected resource without its usage description in
/// Info.plist. Services check here first and report "not available" instead.
enum UsageDescriptions {
    static func has(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }
}

/// Keeps the screen on while the hub shows, and dims it for night mode. Both are restored to
/// what they were when the hub goes away.
@MainActor
final class ScreenController {
    private var idleTimerBefore: Bool?
    private var brightnessBefore: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    func setKeepAwake(_ keepAwake: Bool) {
        if idleTimerBefore == nil {
            idleTimerBefore = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }

    func setNightBrightness(_ brightness: Double?) {
        guard let screen else { return }
        if let brightness {
            if brightnessBefore == nil {
                brightnessBefore = screen.brightness
            }
            screen.brightness = min(screen.brightness, CGFloat(brightness))
        } else if let before = brightnessBefore {
            screen.brightness = before
            brightnessBefore = nil
        }
    }

    func restore() {
        if let idleTimerBefore {
            UIApplication.shared.isIdleTimerDisabled = idleTimerBefore
            self.idleTimerBefore = nil
        }
        setNightBrightness(nil)
    }
}
