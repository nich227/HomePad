import Foundation
import HomePadAssistant
import HomePadAssistantCore
import HomePadBeam
import HomePadBeamCore
import HomePadCore
import HomePadFace
import HomePadKiosk
import HomePadKioskCore
import HomePadMessaging
import HomePadMessagingCore
import HomePadSettingsCatalog
import HomePadUI
import HomePadUICore
import Observation
import SwiftUI

/// Everything the hub (iPad) runs.
@MainActor
struct HubServices {
    let link: PeerLink
    let receiver: BeamReceiver
    let sharePlay: SharePlayCoordinator
    let projection: ProjectionClient
    let intercom: HouseholdIntercom
    let faces: FaceRecognitionService
    let deviceUnlock: DeviceBiometricUnlock
    let kiosk: KioskLockController
    let environment: HubEnvironment
    let navigator: HubNavigator
    let broadcaster: HubSummaryBroadcaster
    let assistant: AssistantEngine
    /// Held here because the engine keeps only what it needs of it.
    let assistantBridge: HubAssistantBridge
}

/// Everything a companion (iPhone) runs.
@MainActor
struct CompanionServices {
    let link: PeerLink
    let sender: BeamSender
    let sharePlay: SharePlayCoordinator
    let host: ProjectionHost
    let intercom: HouseholdIntercom
    let summary: HubSummaryReceiver
    let notifier: LocalNotifier
}

/// Builds the feature packages for the role this device plays and keeps them in step with the
/// scene and with Settings.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case starting
        case hub(HubServices)
        case companion(CompanionServices)
        case failed(String)
    }

    let settings: HomePadSettings
    let session: HouseholdSession
    /// HomePad runs only while Apple Intelligence is available on this device.
    let gate = AppleIntelligenceGate()
    private(set) var phase = Phase.starting

    @ObservationIgnored private var configuredRole: DeviceRole?
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var isRecognitionStarted = false
    /// Ends the grace period of someone who stepped away, once it runs out.
    @ObservationIgnored private var lingerClock: Task<Void, Never>?

    init() {
        let settings = HomePadSettings()
        settings.register(SettingsCatalog.descriptors)
        self.settings = settings

        // UI tests may ask for a sample household kept in memory. No hook is set otherwise.
        let store: any ProfileStore = HubTestHooks.current.sampleProfileStore
            ?? (try? FileProfileStore.applicationSupport())
            ?? InMemoryProfileStore()
        session = HouseholdSession(
            store: store,
            requiresCompanionForPersonalContent: settings[GeneralSettings.requireCompanionForPersonalContent],
            lingerDuration: GeneralSettings.lingerDuration(setting: settings[GeneralSettings.staySignedInSeconds])
        )
        ExtensionSettingsMirror.copy()

        // A companion is built at once: Shortcuts can run an intent before any scene exists.
        if gate.mayRun, HomePadRootView.role(settings: settings) == .companion {
            startCompanion()
        }
    }

    /// Builds the services for `role`, or stops them all while the gate does not let HomePad run.
    func configure(for role: DeviceRole, mayRun: Bool) async {
        guard mayRun else {
            await tearDown()
            return
        }
        guard configuredRole != role else { return }
        await tearDown()
        switch role {
        case .companion:
            startCompanion()
        case .hub:
            await startHub()
        }
        applyScenePhase()
    }

    /// Starts face recognition. The hub calls this once its first-run welcome is out of the
    /// way, so the camera prompt appears over the face and not over the welcome.
    func startRecognition() {
        guard case .hub(let hub) = phase, !isRecognitionStarted else { return }
        isRecognitionStarted = true
        Task { await hub.faces.start() }
    }

    func scenePhaseChanged(to scenePhase: ScenePhase) {
        isSceneActive = scenePhase == .active
        if scenePhase == .active {
            gate.refresh()
            settings.refresh()
            session.requiresCompanionForPersonalContent = settings[GeneralSettings.requireCompanionForPersonalContent]
            session.lingerDuration = GeneralSettings.lingerDuration(setting: settings[GeneralSettings.staySignedInSeconds])
            ExtensionSettingsMirror.copy()
        }
        applyScenePhase(background: scenePhase == .background)
    }

    private func applyScenePhase(background: Bool = false) {
        switch phase {
        case .hub(let hub):
            hub.receiver.setSceneActive(isSceneActive)
            if isSceneActive {
                hub.kiosk.sceneBecameActive()
            } else if background {
                hub.kiosk.sceneEnteredBackground()
            }
        case .companion(let companion):
            companion.sender.setSceneActive(isSceneActive)
        case .starting, .failed:
            break
        }
    }

    private func startCompanion() {
        do {
            let link = try BeamEnvironment.makePeerLink(role: .companion, settings: settings)
            let notifier = LocalNotifier()
            let sender = BeamSender(link: link, settings: settings)
            let sharePlay = SharePlayCoordinator(settings: settings)
            let host = ProjectionHost(channel: link, settings: settings)
            let intercom = HouseholdIntercom(channel: link, settings: settings, notifier: notifier)
            let summary = HubSummaryReceiver()

            sender.start()
            sharePlay.start()
            host.start()
            intercom.start()
            summary.start(channel: link)

            let handlers = HomePadIntentHandlers.shared
            handlers.register(host: host)
            handlers.beam = { url in
                switch await sender.send(url.absoluteString, title: nil, to: nil) {
                case .delivered: .delivered(hubCount: 1)
                case .failed, .idle, .sending: .noHubReachable
                }
            }
            HomePadAppShortcuts.updateAppShortcutParameters()

            phase = .companion(CompanionServices(
                link: link, sender: sender, sharePlay: sharePlay, host: host,
                intercom: intercom, summary: summary, notifier: notifier
            ))
            configuredRole = .companion
        } catch {
            phase = .failed(String(localized: "The pairing store could not be opened."))
        }
    }

    private func startHub() async {
        do {
            let link = try BeamEnvironment.makePeerLink(role: .hub, settings: settings)
            let receiver = BeamReceiver(link: link, session: session, settings: settings)
            let sharePlay = SharePlayCoordinator(settings: settings)
            let projection = ProjectionClient(channel: link, session: session)
            let intercom = HouseholdIntercom(channel: link, settings: settings, session: session)
            let embedder = await FaceEmbedderFactory.loadDefault()
            let faces = FaceRecognitionService(session: session, settings: settings, embedder: embedder)
            let deviceUnlock = DeviceBiometricUnlock(session: session, settings: settings, service: faces)
            let kiosk = KioskLockController(settings: settings, system: LiveKioskSystem())
            let navigator = HubNavigator()

            // The Mirror shares the recognition camera: an iPad runs one front camera session.
            let live = HubEnvironment.live()
            // The sample environment brings its own stand-in for the recipe model.
            let recipes = HubTestHooks.current.usesSampleData
                ? live.recipes
                : RecipeLibrary(enhancer: HubRecipeEnhancer(formatter: RecipeFormatters.make(settings: settings)))
            let environment = HubEnvironment(
                layoutStore: live.layoutStore,
                timers: live.timers,
                alarms: live.alarms,
                home: live.home,
                music: live.music,
                camera: SharedMirrorCamera(faces: faces),
                weather: live.weather,
                photos: live.photos,
                recipes: recipes
            )

            // The Assistant and Siri's hub intents act through one bridge, under one set of rules.
            let bridge = HubAssistantBridge(
                session: session, settings: settings, environment: environment, navigator: navigator,
                receiver: receiver, intercom: intercom, projection: projection, link: link
            )
            let assistant = AssistantEngine(actions: bridge, hub: bridge, session: session, settings: settings)
            AssistantIntentHandlers.shared.register(engine: assistant)

            receiver.start()
            sharePlay.attach(to: receiver)
            sharePlay.start()
            projection.start()
            intercom.start()
            kiosk.start()

            phase = .hub(HubServices(
                link: link, receiver: receiver, sharePlay: sharePlay, projection: projection,
                intercom: intercom, faces: faces, deviceUnlock: deviceUnlock, kiosk: kiosk, environment: environment,
                navigator: navigator, broadcaster: HubSummaryBroadcaster(channel: link),
                assistant: assistant, assistantBridge: bridge
            ))
            configuredRole = .hub
            lingerClock = Task { [session] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    session.endLingerIfDue()
                }
            }
        } catch {
            phase = .failed(String(localized: "The pairing store could not be opened."))
        }
    }

    private func tearDown() async {
        switch phase {
        case .hub(let hub):
            AssistantIntentHandlers.shared.perform = nil
            hub.assistant.dismiss()
            hub.receiver.setSceneActive(false)
            hub.projection.stop()
            hub.intercom.stop()
            hub.kiosk.stop()
            await hub.faces.stop()
        case .companion(let companion):
            companion.sender.setSceneActive(false)
            companion.host.stop()
            companion.intercom.stop()
            companion.summary.stop()
        case .starting, .failed:
            break
        }
        lingerClock?.cancel()
        lingerClock = nil
        phase = .starting
        configuredRole = nil
        isRecognitionStarted = false
    }
}

/// Extensions run in their own process and cannot read the app's preferences, so the few they
/// need are copied into the app group's defaults.
enum ExtensionSettingsMirror {
    static func copy(from source: UserDefaults = .standard, to group: UserDefaults? = UserDefaults(suiteName: HomePadIdentifiers.appGroup)) {
        guard let group else { return }
        for key in SettingsCatalog.sharedWithExtensions {
            if let value = source.object(forKey: key) {
                group.set(value, forKey: key)
            } else {
                group.removeObject(forKey: key)
            }
        }
    }
}
