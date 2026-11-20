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
        let hooks = HubTestHooks.current
        if hooks.usesSampleData {
            return preview(runningTimer: false, recipePage: SampleContent.recipePage)
        }
        let stored = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HomePad", isDirectory: true)
            .appendingPathComponent("UI", isDirectory: true)
        let base = hooks.isEphemeral ? nil : stored
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
    public static func preview(runningTimer: Bool = true, recipePage: String? = nil) -> HubEnvironment {
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
            precipitationChance: 0.3,
            asOf: Date()
        )))
        weather.configure(source: .current, custom: nil)
        weather.begin()
        return HubEnvironment(
            layoutStore: InMemoryLayoutStore(),
            timers: timers,
            alarms: AlarmCenter(),
            home: PreviewHomeService(),
            music: PreviewMusicService(),
            camera: PreviewCameraService(),
            weather: weather,
            photos: FacePhotoLibrary(directory: nil),
            recipes: RecipeLibrary(loader: FixedRecipePageLoader(html: recipePage), enhancer: SampleRecipeEnhancer())
        )
    }
}

extension HubTestHooks {
    /// The switches for this launch. Read once, and only in debug builds.
    public static let current: HubTestHooks = {
        #if DEBUG
        return HubTestHooks(environment: ProcessInfo.processInfo.environment)
        #else
        return .none
        #endif
    }()

    /// The household the UI tests run against, kept in memory. Nil means use the real store.
    public var sampleProfileStore: (any ProfileStore)? {
        guard usesSampleData else { return nil }
        return InMemoryProfileStore(profiles: [
            HouseholdProfile(name: "Erica", tint: .purple),
            HouseholdProfile(name: "Danny", tint: .blue),
        ])
    }
}

/// Made-up content for previews and UI tests.
enum SampleContent {
    static var hubSummary: HubStatusSummary {
        let now = Date()
        return HubStatusSummary(
            surface: .app(.recipes),
            face: .flow,
            profileName: "Erica",
            timers: [HubTimer(name: "Pasta", duration: 900, state: .running(endsAt: now.addingTimeInterval(540)), createdAt: now)],
            nowPlaying: NowPlaying(title: "Morning Light", artist: "The Placeholders", isPlaying: true),
            isNight: false,
            at: now
        )
    }

    static let recipePage = """
    <html><head><script type="application/ld+json">
    {"@context":"https://schema.org","@type":"Recipe","name":"Butternut Squash Soup",
     "author":{"@type":"Organization","name":"Home Cookbook"},"recipeYield":"Serves 4",
     "prepTime":"PT10M","cookTime":"PT25M","totalTime":"PT35M",
     "recipeIngredient":["1 butternut squash, peeled and cubed","1 yellow onion, chopped","2 cloves garlic","4 cups vegetable stock","2 tablespoons olive oil","Fresh sage leaves","Salt and pepper"],
     "recipeInstructions":[
       {"@type":"HowToStep","text":"Heat the oil in a large pot. Cook the onion and garlic until soft, about 5 minutes."},
       {"@type":"HowToStep","text":"Add the squash and the stock. Bring to a boil, then simmer for 20 minutes until the squash is tender."},
       {"@type":"HowToStep","text":"Blend until smooth. Season with salt and pepper."},
       {"@type":"HowToStep","text":"Fry the sage leaves for 30 seconds and scatter them over each bowl."}]}
    </script></head><body></body></html>
    """
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

    /// The screen's brightness now, 0...1, or nil when no screen is in front.
    var brightness: Double? {
        screen.map { Double($0.brightness) }
    }

    /// Night Mode dims the screen once, on entering, and remembers what it was. Nil puts that
    /// back. Dimming only on entering leaves the control center's slider free to raise it.
    func setNightBrightness(_ brightness: Double?) {
        guard let screen else { return }
        if let brightness {
            guard brightnessBefore == nil else { return }
            brightnessBefore = screen.brightness
            screen.brightness = min(screen.brightness, CGFloat(brightness))
        } else if let before = brightnessBefore {
            screen.brightness = before
            brightnessBefore = nil
        }
    }

    /// The brightness slider in the control center. The system has no other brightness an app
    /// may set, so this is the screen's own.
    func setBrightness(_ brightness: Double) {
        screen?.brightness = CGFloat(brightness)
    }

    func restore() {
        if let idleTimerBefore {
            UIApplication.shared.isIdleTimerDisabled = idleTimerBefore
            self.idleTimerBefore = nil
        }
        setNightBrightness(nil)
    }
}
