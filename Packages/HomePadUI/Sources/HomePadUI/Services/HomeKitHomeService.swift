import Foundation
import HomeKit
import HomePadUICore
import Observation
import SwiftUI

/// Reads and controls the primary home. The home manager is created on `start`, because creating
/// it is what triggers the system's permission prompt.
@MainActor
@Observable
public final class HomeKitHomeService: NSObject, HomeService {
    public private(set) var snapshot: HomeSnapshot = .empty
    public private(set) var access: HomeAccess = .unknown
    public private(set) var lastError: HomeControlError?

    @ObservationIgnored private var manager: HMHomeManager?
    @ObservationIgnored private var cameraProfiles: [String: HMCameraProfile] = [:]

    public override init() {
        super.init()
    }

    public func start() {
        guard manager == nil else { return }
        guard UsageDescriptions.has("NSHomeKitUsageDescription") else {
            access = .denied
            return
        }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    private var home: HMHome? {
        guard let manager else { return nil }
        return manager.homes.first(where: \.isPrimary) ?? manager.homes.first
    }

    private func rebuild() {
        guard let manager else { return }
        let status = manager.authorizationStatus
        guard status.contains(.authorized) else {
            access = status.contains(.determined) ? .denied : .unknown
            snapshot = .empty
            return
        }
        guard let home else {
            access = .noHomes
            snapshot = .empty
            return
        }
        home.delegate = self
        var accessories: [HomeAccessory] = []
        var thermostats: [HomeThermostat] = []
        var cameras: [HomeCamera] = []
        var profiles: [String: HMCameraProfile] = [:]
        for accessory in home.accessories {
            accessory.delegate = self
            let room = accessory.room?.name ?? ""
            for service in accessory.services {
                let id = service.uniqueIdentifier.uuidString
                if service.serviceType == HMServiceTypeThermostat {
                    let current = Self.double(service, HMCharacteristicTypeCurrentTemperature) ?? 0
                    let target = Self.double(service, HMCharacteristicTypeTargetTemperature) ?? current
                    thermostats.append(HomeThermostat(id: id, name: service.name, roomName: room, currentCelsius: current, targetCelsius: target))
                } else if let kind = Self.kind(of: service) {
                    accessories.append(HomeAccessory(
                        id: id,
                        name: service.name,
                        roomName: room,
                        kind: kind,
                        isOn: Self.isOn(service, kind: kind),
                        brightness: Self.double(service, HMCharacteristicTypeBrightness).map { Int($0.rounded()) },
                        isReachable: accessory.isReachable
                    ))
                }
            }
            for profile in accessory.cameraProfiles ?? [] {
                let id = profile.uniqueIdentifier.uuidString
                profiles[id] = profile
                cameras.append(HomeCamera(id: id, name: accessory.name, roomName: room))
            }
        }
        let scenes = home.actionSets
            .filter { !$0.actions.isEmpty }
            .map { HomeScene(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        cameraProfiles = profiles
        access = .ready
        snapshot = HomeSnapshot(homeName: home.name, accessories: accessories, scenes: scenes, thermostats: thermostats, cameras: cameras)
    }

    /// Asks every tracked characteristic for a fresh value and for change notifications.
    private func refreshValues() {
        guard let home else { return }
        let tracked = [
            HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness, HMCharacteristicTypeActive,
            HMCharacteristicTypeCurrentLockMechanismState, HMCharacteristicTypeCurrentTemperature,
            HMCharacteristicTypeTargetTemperature,
        ]
        let characteristics = home.accessories
            .filter(\.isReachable)
            .flatMap(\.services)
            .flatMap(\.characteristics)
            .filter { tracked.contains($0.characteristicType) }
        Task { [weak self] in
            for characteristic in characteristics {
                try? await characteristic.readValue()
                if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                    try? await characteristic.enableNotification(true)
                }
            }
            self?.rebuild()
        }
    }

    public func setPower(_ isOn: Bool, accessoryID: String) async {
        guard let service = service(id: accessoryID), let kind = Self.kind(of: service) else {
            lastError = .unknownAccessory
            return
        }
        switch kind {
        case .lock:
            let state: HMCharacteristicValueLockMechanismState = isOn ? .secured : .unsecured
            await write(state.rawValue, to: service, HMCharacteristicTypeTargetLockMechanismState)
        case .fan where Self.characteristic(service, HMCharacteristicTypePowerState) == nil:
            await write(isOn ? 1 : 0, to: service, HMCharacteristicTypeActive)
        default:
            await write(isOn, to: service, HMCharacteristicTypePowerState)
        }
    }

    public func setBrightness(_ brightness: Int, accessoryID: String) async {
        guard let service = service(id: accessoryID) else {
            lastError = .unknownAccessory
            return
        }
        let normalized = BrightnessMath.normalized(Double(brightness))
        if normalized.isOn {
            await write(normalized.brightness, to: service, HMCharacteristicTypeBrightness)
        }
        await write(normalized.isOn, to: service, HMCharacteristicTypePowerState)
    }

    public func runScene(id: String) async {
        guard let home, let scene = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == id }) else {
            lastError = .unknownAccessory
            return
        }
        lastError = (try? await home.executeActionSet(scene)) == nil ? .failed : nil
        rebuild()
    }

    public func setTargetTemperature(celsius: Double, thermostatID: String) async {
        guard let service = service(id: thermostatID) else {
            lastError = .unknownAccessory
            return
        }
        await write(celsius, to: service, HMCharacteristicTypeTargetTemperature)
    }

    public func cameraView(id: String, live: Bool) -> AnyView {
        guard let profile = cameraProfiles[id] else { return AnyView(CameraPlaceholderView()) }
        return AnyView(HomeKitCameraView(profile: profile, live: live).id("\(id)-\(live)"))
    }

    private func service(id: String) -> HMService? {
        home?.accessories.flatMap(\.services).first { $0.uniqueIdentifier.uuidString == id }
    }

    private func write(_ value: Any, to service: HMService, _ type: String) async {
        guard let characteristic = Self.characteristic(service, type) else {
            lastError = .notSupported
            return
        }
        lastError = (try? await characteristic.writeValue(value)) == nil ? .failed : nil
        rebuild()
    }

    private static func characteristic(_ service: HMService, _ type: String) -> HMCharacteristic? {
        service.characteristics.first { $0.characteristicType == type }
    }

    private static func double(_ service: HMService, _ type: String) -> Double? {
        (characteristic(service, type)?.value as? NSNumber)?.doubleValue
    }

    private static func kind(of service: HMService) -> HomeAccessoryKind? {
        switch service.serviceType {
        case HMServiceTypeLightbulb: .light
        case HMServiceTypeOutlet: .outlet
        case HMServiceTypeFan: .fan
        case HMServiceTypeLockMechanism: .lock
        case HMServiceTypeSwitch: .other
        default: nil
        }
    }

    private static func isOn(_ service: HMService, kind: HomeAccessoryKind) -> Bool {
        switch kind {
        case .lock:
            return double(service, HMCharacteristicTypeCurrentLockMechanismState) == Double(HMCharacteristicValueLockMechanismState.secured.rawValue)
        default:
            let power = double(service, HMCharacteristicTypePowerState) ?? double(service, HMCharacteristicTypeActive) ?? 0
            return power > 0
        }
    }
}

// The home framework calls its delegates on the main queue but does not say so in its headers,
// so each callback hops to the main actor explicitly.
extension HomeKitHomeService: HMHomeManagerDelegate, HMHomeDelegate, HMAccessoryDelegate {
    public nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.rebuild()
            self.refreshValues()
        }
    }

    public nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in self.rebuild() }
    }

    public nonisolated func homeDidUpdateName(_ home: HMHome) {
        Task { @MainActor in self.rebuild() }
    }

    public nonisolated func home(_ home: HMHome, didAdd accessory: HMAccessory) {
        Task { @MainActor in
            self.rebuild()
            self.refreshValues()
        }
    }

    public nonisolated func home(_ home: HMHome, didRemove accessory: HMAccessory) {
        Task { @MainActor in self.rebuild() }
    }

    public nonisolated func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        Task { @MainActor in self.rebuild() }
    }

    public nonisolated func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in self.rebuild() }
    }
}

/// Shows a camera. Tiles use snapshots refreshed on a timer, because a home can stream only a
/// few cameras at once; the full-screen view asks for a live stream.
private struct HomeKitCameraView: UIViewRepresentable {
    let profile: HMCameraProfile
    let live: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(profile: profile, live: live)
    }

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView()
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ uiView: HMCameraView, context: Context) {}

    static func dismantleUIView(_ uiView: HMCameraView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, HMCameraSnapshotControlDelegate, HMCameraStreamControlDelegate {
        private let profile: HMCameraProfile
        private let live: Bool
        private weak var view: HMCameraView?
        private var refresh: Task<Void, Never>?

        init(profile: HMCameraProfile, live: Bool) {
            self.profile = profile
            self.live = live
        }

        func attach(_ view: HMCameraView) {
            self.view = view
            view.cameraSource = profile.snapshotControl?.mostRecentSnapshot
            profile.snapshotControl?.delegate = self
            if live, let stream = profile.streamControl {
                stream.delegate = self
                stream.startStream()
                return
            }
            refresh = Task { [weak self] in
                while !Task.isCancelled {
                    self?.profile.snapshotControl?.takeSnapshot()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }

        func stop() {
            refresh?.cancel()
            if live {
                profile.streamControl?.stopStream()
            }
        }

        private func showLatest() {
            if live, let stream = profile.streamControl?.cameraStream {
                view?.cameraSource = stream
            } else {
                view?.cameraSource = profile.snapshotControl?.mostRecentSnapshot
            }
        }

        nonisolated func cameraSnapshotControl(_ cameraSnapshotControl: HMCameraSnapshotControl, didTake snapshot: HMCameraSnapshot?, error: (any Error)?) {
            Task { @MainActor in self.showLatest() }
        }

        nonisolated func cameraSnapshotControlDidUpdateMostRecentSnapshot(_ cameraSnapshotControl: HMCameraSnapshotControl) {
            Task { @MainActor in self.showLatest() }
        }

        nonisolated func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) {
            Task { @MainActor in self.showLatest() }
        }

        nonisolated func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl, didStopStreamWithError error: (any Error)?) {
            Task { @MainActor in self.showLatest() }
        }
    }
}
