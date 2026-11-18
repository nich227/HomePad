import Foundation

public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var duration: TimeInterval
    public var elapsed: TimeInterval

    public init(title: String, artist: String = "", album: String = "", isPlaying: Bool, duration: TimeInterval = 0, elapsed: TimeInterval = 0) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
    }

    /// 0...1 for the scrubber, 0 when the length is unknown.
    public var progress: Double {
        guard duration > 0, elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    public var remaining: TimeInterval {
        max(0, duration - max(0, elapsed.isFinite ? elapsed : 0))
    }
}

public enum TemperatureUnit: String, Sendable {
    case celsius, fahrenheit

    public func value(fromCelsius celsius: Double) -> Double {
        self == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// Whole degrees, the way a thermostat or weather tile shows them.
    public func rounded(fromCelsius celsius: Double) -> Int {
        Int(value(fromCelsius: celsius).rounded())
    }
}

public enum TemperatureUnitSetting: String, Sendable {
    case automatic, celsius, fahrenheit

    public func resolved(localeUsesFahrenheit: Bool) -> TemperatureUnit {
        switch self {
        case .automatic: localeUsesFahrenheit ? .fahrenheit : .celsius
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        }
    }
}

public struct WeatherSnapshot: Equatable, Sendable {
    public var locationName: String
    public var temperatureCelsius: Double
    public var highCelsius: Double
    public var lowCelsius: Double
    public var conditionText: String
    public var symbolName: String
    public var humidity: Double?
    public var windKilometersPerHour: Double?
    public var sunset: Date?
    /// 0...1 for today, nil when the source does not say.
    public var precipitationChance: Double?
    public var asOf: Date

    public init(
        locationName: String,
        temperatureCelsius: Double,
        highCelsius: Double,
        lowCelsius: Double,
        conditionText: String,
        symbolName: String,
        humidity: Double? = nil,
        windKilometersPerHour: Double? = nil,
        sunset: Date? = nil,
        precipitationChance: Double? = nil,
        asOf: Date
    ) {
        self.locationName = locationName
        self.temperatureCelsius = temperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.conditionText = conditionText
        self.symbolName = symbolName
        self.humidity = humidity
        self.windKilometersPerHour = windKilometersPerHour
        self.sunset = sunset
        self.precipitationChance = precipitationChance.map { min(max($0, 0), 1) }
        self.asOf = asOf
    }

    /// Weather older than this is shown as unavailable instead of as current.
    public static let staleAfter: TimeInterval = 2 * 60 * 60

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(asOf) > Self.staleAfter
    }
}

/// What the drawn sky shows. Chosen from the condition's symbol, which every source provides.
public enum SkyKind: String, CaseIterable, Sendable {
    case clear, cloudy, rain, snow, storm, fog, night

    public init(symbolName: String?) {
        let name = symbolName ?? ""
        if name.contains("bolt") {
            self = .storm
        } else if name.contains("snow") || name.contains("sleet") || name.contains("hail") {
            self = .snow
        } else if name.contains("rain") || name.contains("drizzle") {
            self = .rain
        } else if name.contains("fog") || name.contains("haze") || name.contains("smoke") {
            self = .fog
        } else if name.contains("moon") {
            self = .night
        } else if name.contains("cloud") {
            self = .cloudy
        } else {
            self = .clear
        }
    }

    /// Whether drops or flakes fall across the sky.
    public var hasPrecipitation: Bool {
        self == .rain || self == .snow || self == .storm
    }
}

public enum WeatherError: Error, Equatable, Sendable {
    /// No location was entered, or no weather source is linked.
    case notConfigured
    case unavailable
}

public protocol WeatherProviding: Sendable {
    func currentWeather() async throws(WeatherError) -> WeatherSnapshot
}

/// Used until a real source is configured. Weather is optional: the hub works without it.
public struct PlaceholderWeatherProvider: WeatherProviding {
    public init() {}

    public func currentWeather() async throws(WeatherError) -> WeatherSnapshot {
        throw .notConfigured
    }
}

/// A fixed answer, for previews and tests.
public struct FixedWeatherProvider: WeatherProviding {
    private let snapshot: WeatherSnapshot

    public init(snapshot: WeatherSnapshot) {
        self.snapshot = snapshot
    }

    public func currentWeather() async throws(WeatherError) -> WeatherSnapshot {
        snapshot
    }
}
