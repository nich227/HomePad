import HomePadCore
import HomePadUICore
import SwiftUI
import UIKit

/// The app's root: the hub on an iPad, the companion on an iPhone. The "This Device Is" setting
/// overrides the device default.
public struct HomePadRootView: View {
    private let session: HouseholdSession
    private let settings: HomePadSettings
    private let slots: HubFeatureSlots
    private let environment: HubEnvironment
    private let navigator: HubNavigator
    private let facePosition: (@MainActor () -> FacePosition?)?
    private let ambientLight: (@MainActor () -> AmbientLightHint?)?
    private let hubSummary: HubStatusSummary?
    private let onHubSummaryChange: (@MainActor (HubStatusSummary) -> Void)?
    private let roleOverride: DeviceRole?

    /// - Parameters:
    ///   - hubSummary: Companion only. The latest summary received from the hub.
    ///   - onHubSummaryChange: Hub only. Called when what the hub shows changes.
    ///   - roleOverride: Forces a role regardless of device and settings, for previews.
    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        slots: HubFeatureSlots = HubFeatureSlots(),
        environment: HubEnvironment,
        navigator: HubNavigator,
        facePosition: (@MainActor () -> FacePosition?)? = nil,
        ambientLight: (@MainActor () -> AmbientLightHint?)? = nil,
        hubSummary: HubStatusSummary? = nil,
        onHubSummaryChange: (@MainActor (HubStatusSummary) -> Void)? = nil,
        roleOverride: DeviceRole? = nil
    ) {
        self.session = session
        self.settings = settings
        self.slots = slots
        self.environment = environment
        self.navigator = navigator
        self.facePosition = facePosition
        self.ambientLight = ambientLight
        self.hubSummary = hubSummary
        self.onHubSummaryChange = onHubSummaryChange
        self.roleOverride = roleOverride
    }

    /// The role this device plays right now.
    public static func role(settings: HomePadSettings, override: DeviceRole? = nil) -> DeviceRole {
        override ?? GeneralSettings.resolvedRole(
            setting: settings[GeneralSettings.deviceRole],
            isPad: UIDevice.current.userInterfaceIdiom == .pad
        )
    }

    public var body: some View {
        switch Self.role(settings: settings, override: roleOverride) {
        case .hub:
            HubRootView(
                session: session,
                settings: settings,
                slots: slots,
                environment: environment,
                navigator: navigator,
                facePosition: facePosition,
                ambientLight: ambientLight,
                onSummaryChange: onHubSummaryChange
            )
        case .companion:
            CompanionRootView(session: session, settings: settings, slots: slots, hubSummary: hubSummary)
        }
    }
}

/// Sends the hub's summary to every connected companion.
public struct HubSummaryBroadcaster: Sendable {
    private let channel: any PeerChannel

    public init(channel: any PeerChannel) {
        self.channel = channel
    }

    /// Best effort: with no companion connected there is nobody to tell.
    public func publish(_ summary: HubStatusSummary) async {
        try? await channel.send(summary, on: HubStatusSummary.channel)
    }
}

/// Keeps the latest hub summary on a companion.
@MainActor
@Observable
public final class HubSummaryReceiver {
    public private(set) var summary: HubStatusSummary?
    @ObservationIgnored private var listener: Task<Void, Never>?

    public init() {}

    /// Starts listening. Calling again replaces the previous channel.
    public func start(channel: any PeerChannel) {
        listener?.cancel()
        let stream = channel.decoded(HubStatusSummary.self, on: HubStatusSummary.channel)
        listener = Task { [weak self] in
            for await update in stream {
                self?.summary = update.message
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }
}
