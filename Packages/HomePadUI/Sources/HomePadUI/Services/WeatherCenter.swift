import CoreLocation
import Foundation
import HomePadUICore
import MapKit
import Observation
import SwiftUI
import WeatherKit

/// Weather from the system weather service for one place. Needs the WeatherKit entitlement;
/// without it every request fails and the hub shows weather as unavailable.
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
            precipitationChance: today?.precipitationChance,
            asOf: current.date
        )
    }
}

/// Where the hub is, for the weather. The real one asks Location Services; previews use a fixed
/// place.
@MainActor
public protocol LocationProviding: AnyObject {
    var permission: LocationPermission { get }
    /// The hub's position with its place name, once both are known.
    var fix: WeatherLocation? { get }
    /// Called when the permission or the fix changes.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Shows the system prompt when the person has not answered it yet.
    func requestPermission()
    /// Asks for one position. Does nothing without permission.
    func locate()
}

/// A place that never moves and needs no permission.
@MainActor
public final class FixedLocationProvider: LocationProviding {
    public let permission: LocationPermission
    public let fix: WeatherLocation?
    public var onChange: (@MainActor () -> Void)?

    public init(permission: LocationPermission = .allowed, fix: WeatherLocation?) {
        self.permission = permission
        self.fix = fix
    }

    public func requestPermission() {}
    public func locate() {}
}

/// Location Services, when in use only, at city accuracy. The place name comes from reverse
/// geocoding the position.
@MainActor
public final class SystemLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    public private(set) var permission: LocationPermission = .notDetermined
    public private(set) var fix: WeatherLocation?
    public var onChange: (@MainActor () -> Void)?
    private let manager = CLLocationManager()
    private var naming: Task<Void, Never>?

    override public init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        permission = Self.permission(for: manager.authorizationStatus)
        // Without the usage description the system would end the app on the request.
        if !UsageDescriptions.has("NSLocationWhenInUseUsageDescription") {
            permission = .denied
        }
    }

    private static func permission(for status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        default: .denied
        }
    }

    public func requestPermission() {
        guard permission == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    public func locate() {
        guard permission == .allowed else { return }
        manager.requestLocation()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.permission = Self.permission(for: status)
            self.onChange?()
            self.locate()
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.name(location)
        }
    }

    /// A failed request leaves the last fix in place. The weather shows "finding this place"
    /// until one arrives.
    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    private func name(_ location: CLLocation) {
        naming?.cancel()
        naming = Task { [weak self] in
            let items = try? await MKReverseGeocodingRequest(location: location)?.mapItems
            guard !Task.isCancelled, let self else { return }
            let city = items?.first?.addressRepresentations?.cityName ?? ""
            self.fix = WeatherLocation(name: city, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.onChange?()
        }
    }
}

/// Finds the place, caches the latest weather for it, and refreshes on a slow cadence. With
/// nothing to show it says why, so a face can explain itself.
@MainActor
@Observable
public final class WeatherCenter {
    public private(set) var snapshot: WeatherSnapshot?
    /// Why there is no weather. Nil while there is, and while the first answer is on its way.
    public private(set) var problem: WeatherProblem?

    @ObservationIgnored private let makeProvider: @Sendable (WeatherLocation) -> any WeatherProviding
    @ObservationIgnored private let locator: any LocationProviding
    @ObservationIgnored private var source = WeatherLocationSource.current
    @ObservationIgnored private var custom: WeatherLocation?
    @ObservationIgnored private var hasBegun = false
    @ObservationIgnored private var place: WeatherLocation?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let refreshInterval: Duration = .seconds(30 * 60)

    public init(makeProvider: @escaping @Sendable (WeatherLocation) -> any WeatherProviding, locator: any LocationProviding) {
        self.makeProvider = makeProvider
        self.locator = locator
        locator.onChange = { [weak self] in self?.refresh() }
    }

    /// One provider for a fixed place, for previews and tests.
    public convenience init(provider: any WeatherProviding, place: WeatherLocation = WeatherLocation(name: "San Francisco", latitude: 37.77, longitude: -122.42)) {
        self.init(makeProvider: { _ in provider }, locator: FixedLocationProvider(fix: place))
    }

    /// The live source: Location Services for the place and the system weather service.
    public static func live() -> WeatherCenter {
        WeatherCenter(makeProvider: { WeatherKitWeatherProvider(location: $0) }, locator: SystemLocationProvider())
    }

    /// Sets where the weather is for, from Settings.
    public func configure(source: WeatherLocationSource, custom: WeatherLocation?) {
        guard source != self.source || custom != self.custom || loop == nil else { return }
        self.source = source
        self.custom = custom
        refresh()
    }

    /// Call when weather is first on screen. This is the moment the hub may ask for Location
    /// Services, so the prompt arrives when its reason is visible.
    public func begin() {
        guard !hasBegun else { return }
        hasBegun = true
        if source == .current {
            locator.requestPermission()
            locator.locate()
        }
        refresh()
    }

    private func refresh() {
        switch WeatherPlace.resolve(source: source, custom: custom, permission: locator.permission, fix: locator.fix) {
        case .unavailable(let problem):
            loop?.cancel()
            loop = nil
            place = nil
            snapshot = nil
            self.problem = problem
        case .ready(let location):
            guard location != place || loop == nil else { return }
            place = location
            start(for: location)
        }
    }

    private func start(for location: WeatherLocation) {
        loop?.cancel()
        let provider = makeProvider(location)
        let interval = refreshInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do throws(HomePadUICore.WeatherError) {
                    let latest = try await provider.currentWeather()
                    guard !Task.isCancelled else { return }
                    self?.snapshot = latest
                    self?.problem = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.snapshot = nil
                    self?.problem = .serviceUnavailable
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}

/// What a face or the Weather app says when there is no weather.
struct WeatherMessage {
    let title: String
    let detail: String
    let symbol: String
    let offersSettings: Bool

    init(problem: WeatherProblem?) {
        offersSettings = problem?.isFixedInSettings ?? false
        switch problem {
        case nil:
            title = String(localized: "Loading Weather")
            detail = ""
            symbol = "cloud.sun.fill"
        case .needsLocationPermission:
            title = String(localized: "Weather Uses Your Location")
            detail = String(localized: "HomePad asks for Location Services to show the weather where the hub is.")
            symbol = "location.fill"
        case .locationDenied:
            title = String(localized: "Location Is Off")
            detail = String(localized: "Allow Location for HomePad in Settings, or choose a custom place there.")
            symbol = "location.slash.fill"
        case .locating:
            title = String(localized: "Finding This Place")
            detail = String(localized: "Waiting for Location Services.")
            symbol = "location.fill"
        case .customLocationMissing:
            title = String(localized: "Enter a Place")
            detail = String(localized: "Custom is chosen in Settings and no coordinates are entered.")
            symbol = "mappin.slash"
        case .serviceUnavailable:
            title = String(localized: "Weather Is Unavailable")
            detail = String(localized: "The weather service did not answer. HomePad will try again.")
            symbol = "cloud.slash.fill"
        }
    }
}
