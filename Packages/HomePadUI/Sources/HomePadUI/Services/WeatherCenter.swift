import CoreLocation
import Foundation
import HomePadUICore
import Observation
import WeatherKit

/// Weather from the system weather service for a place entered in Settings. Needs the WeatherKit
/// entitlement; without it every request fails and the hub shows weather as unavailable.
public struct WeatherKitWeatherProvider: WeatherProviding {
    private let location: WeatherLocation

    public init(location: WeatherLocation) {
        self.location = location
    }

    public func currentWeather() async throws(HomePadUICore.WeatherError) -> WeatherSnapshot {
        let place = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard let weather = try? await WeatherService.shared.weather(for: place) else { throw .unavailable }
        let current = weather.currentWeather
        let today = weather.dailyForecast.first
        let temperature = current.temperature.converted(to: .celsius).value
        return WeatherSnapshot(
            locationName: location.name,
            temperatureCelsius: temperature,
            highCelsius: today?.highTemperature.converted(to: .celsius).value ?? temperature,
            lowCelsius: today?.lowTemperature.converted(to: .celsius).value ?? temperature,
            conditionText: current.condition.description,
            symbolName: current.symbolName,
            humidity: current.humidity,
            windKilometersPerHour: current.wind.speed.converted(to: .kilometersPerHour).value,
            sunset: today?.sun.sunset,
            asOf: current.date
        )
    }
}

/// Caches the latest weather and refreshes it on a slow cadence.
@MainActor
@Observable
public final class WeatherCenter {
    public private(set) var snapshot: WeatherSnapshot?
    public private(set) var error: HomePadUICore.WeatherError?

    @ObservationIgnored private let makeProvider: @Sendable (WeatherLocation?) -> any WeatherProviding
    @ObservationIgnored private var location: WeatherLocation?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let refreshInterval: Duration = .seconds(30 * 60)

    /// `makeProvider` is called again whenever the location in Settings changes.
    public init(makeProvider: @escaping @Sendable (WeatherLocation?) -> any WeatherProviding = { _ in PlaceholderWeatherProvider() }) {
        self.makeProvider = makeProvider
    }

    public convenience init(provider: any WeatherProviding) {
        self.init(makeProvider: { _ in provider })
    }

    /// The live source: the system weather service when a location is set, nothing otherwise.
    public static func live() -> WeatherCenter {
        WeatherCenter { location in
            guard let location else { return PlaceholderWeatherProvider() }
            return WeatherKitWeatherProvider(location: location)
        }
    }

    /// Starts or restarts refreshing for `location`. Does nothing when it has not changed.
    public func configure(location: WeatherLocation?) {
        guard loop == nil || location != self.location else { return }
        self.location = location
        loop?.cancel()
        let provider = makeProvider(location)
        let interval = refreshInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do throws(HomePadUICore.WeatherError) {
                    let latest = try await provider.currentWeather()
                    self?.snapshot = latest
                    self?.error = nil
                } catch {
                    self?.snapshot = nil
                    self?.error = error
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
