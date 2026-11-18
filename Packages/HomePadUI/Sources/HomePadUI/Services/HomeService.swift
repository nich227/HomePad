import Foundation
import HomePadUICore
import Observation
import SwiftUI

public enum HomeControlError: Error, Equatable, Sendable {
    case unknownAccessory
    case notSupported
    case failed
}

/// The home the hub controls. Views read `snapshot` and call the control methods; the real
/// implementation talks to the home framework and previews use an in-memory home.
@MainActor
public protocol HomeService: AnyObject {
    var snapshot: HomeSnapshot { get }
    var access: HomeAccess { get }
    var lastError: HomeControlError? { get }
    /// Asks for access if needed and starts tracking changes. Safe to call more than once.
    func start()
    func setPower(_ isOn: Bool, accessoryID: String) async
    func setBrightness(_ brightness: Int, accessoryID: String) async
    func runScene(id: String) async
    func setTargetTemperature(celsius: Double, thermostatID: String) async
    func setThermostatMode(_ mode: ThermostatMode, thermostatID: String) async
    /// The white of a light, in mireds, for a light that reports one.
    func setColorTemperature(_ mireds: Int, accessoryID: String) async
    /// Turns talking through a camera on or off, for a camera that reports two-way audio and
    /// has a live stream open.
    func setCameraTalk(_ isOn: Bool, cameraID: String) async
    /// A live or recent picture from a camera. `live` asks for a stream instead of snapshots.
    func cameraView(id: String, live: Bool) -> AnyView
}

/// A made-up home for previews and for running without the home entitlement.
@MainActor
@Observable
public final class PreviewHomeService: HomeService {
    public private(set) var snapshot: HomeSnapshot
    public private(set) var access: HomeAccess
    public private(set) var lastError: HomeControlError?

    public init(snapshot: HomeSnapshot = PreviewHomeService.sampleHome, access: HomeAccess = .ready) {
        self.snapshot = snapshot
        self.access = access
    }

    public static let sampleHome = HomeSnapshot(
        homeName: "Home",
        accessories: [
            HomeAccessory(id: "lock", name: "Door Lock", roomName: "Front Door", kind: .lock, isOn: true),
            HomeAccessory(id: "entry", name: "Lights", roomName: "Entryway", kind: .light, isOn: true, brightness: 80, colorTemperature: 370),
            HomeAccessory(id: "bedroom", name: "Lights", roomName: "Bedroom", kind: .light, isOn: true, brightness: 40),
            HomeAccessory(id: "fan", name: "Fan", roomName: "Office", kind: .fan, isOn: true),
            HomeAccessory(id: "outlet", name: "Outlet", roomName: "Office", kind: .outlet, isOn: false),
        ],
        scenes: [HomeScene(id: "arrive", name: "Arrive Home"), HomeScene(id: "night", name: "Good Night")],
        thermostats: [HomeThermostat(id: "thermostat", name: "Thermostat", roomName: "Living Room", currentCelsius: 20.6, targetCelsius: 20, mode: .auto)],
        cameras: [HomeCamera(id: "porch", name: "Porch", roomName: "Front Door")]
    )

    public func start() {}

    public func setPower(_ isOn: Bool, accessoryID: String) async {
        guard let index = snapshot.accessories.firstIndex(where: { $0.id == accessoryID }) else {
            lastError = .unknownAccessory
            return
        }
        snapshot.accessories[index].isOn = isOn
    }

    public func setBrightness(_ brightness: Int, accessoryID: String) async {
        guard let index = snapshot.accessories.firstIndex(where: { $0.id == accessoryID }) else {
            lastError = .unknownAccessory
            return
        }
        let normalized = BrightnessMath.normalized(Double(brightness))
        snapshot.accessories[index].brightness = normalized.brightness
        snapshot.accessories[index].isOn = normalized.isOn
    }

    public func runScene(id: String) async {
        let night = id == "night"
        for index in snapshot.accessories.indices where snapshot.accessories[index].kind == .light {
            snapshot.accessories[index].isOn = !night
        }
    }

    public func setTargetTemperature(celsius: Double, thermostatID: String) async {
        guard let index = snapshot.thermostats.firstIndex(where: { $0.id == thermostatID }) else {
            lastError = .unknownAccessory
            return
        }
        snapshot.thermostats[index].targetCelsius = celsius
    }

    public func setThermostatMode(_ mode: ThermostatMode, thermostatID: String) async {
        guard let index = snapshot.thermostats.firstIndex(where: { $0.id == thermostatID }) else {
            lastError = .unknownAccessory
            return
        }
        snapshot.thermostats[index].mode = mode
    }

    public func setColorTemperature(_ mireds: Int, accessoryID: String) async {
        guard let index = snapshot.accessories.firstIndex(where: { $0.id == accessoryID }) else {
            lastError = .unknownAccessory
            return
        }
        snapshot.accessories[index].colorTemperature = mireds
    }

    public func setCameraTalk(_ isOn: Bool, cameraID: String) async {}

    public func cameraView(id: String, live: Bool) -> AnyView {
        AnyView(CameraPlaceholderView())
    }
}

/// Neutral stand-in for a camera picture: a soft gradient and a camera glyph.
struct CameraPlaceholderView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "video.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.35))
        }
        .accessibilityHidden(true)
    }
}
