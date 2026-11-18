import HomePadAssistant
import HomePadBeam
import HomePadBeamCore
import HomePadCore
import HomePadFace
import HomePadKiosk
import HomePadMessaging
import HomePadMessagingCore
import HomePadUI
import HomePadUICore
import SwiftUI

/// The iPad side: the HomeView-style shell with the feature packages in its slots, plus the
/// banners and the kiosk lock drawn over it.
struct HubSceneView: View {
    let model: AppModel
    let hub: HubServices

    private var audience: AudienceContext {
        AudienceContext(
            isGuest: model.session.isGuest,
            isPersonalContentUnlocked: model.session.isPersonalContentUnlocked,
            setupMode: model.settings[GeneralSettings.setupMode]
        )
    }

    var body: some View {
        HomePadRootView(
            session: model.session,
            settings: model.settings,
            slots: slots,
            environment: hub.environment,
            navigator: hub.navigator,
            facePosition: { [faces = hub.faces] in
                faces.facePosition.map { FacePosition(x: $0.x, y: $0.y) }
            },
            ambientLight: { [faces = hub.faces] in
                Self.ambientLight(isRoomDark: faces.isRoomDark, brightness: faces.roomBrightness)
            },
            onHubSummaryChange: { [broadcaster = hub.broadcaster] summary in
                Task { await broadcaster.publish(summary) }
            },
            onWelcomeFinished: { model.startRecognition() },
            roleOverride: .hub
        )
        .overlay(alignment: .top) {
            // Do Not Disturb in the control center holds the hub's banners back.
            if !hub.navigator.isDoNotDisturbOn {
                VStack(spacing: 12) {
                    BeamApprovalBanner(receiver: hub.receiver, proximity: model.session.proximity)
                    HouseholdNoteBanner(intercom: hub.intercom, proximity: model.session.proximity)
                }
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            KioskLockOverlay(controller: hub.kiosk, showsHints: model.settings[GeneralSettings.setupMode])
                .padding(16)
        }
        .beamIncomingHandlers(hub.receiver)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: hub.receiver.current?.id, initial: true) { _, _ in
            showCurrentBeam()
        }
        .onChange(of: hub.receiver.connectedProfileIDs, initial: true) { _, connected in
            for profile in model.session.profiles {
                model.session.setCompanionPresent(connected.contains(profile.id), for: profile.id)
            }
        }
        .onChange(of: hub.projection.presentationRequest != nil) { _, requested in
            guard requested else { return }
            hub.navigator.open(.projectedApps, context: audience)
        }
    }

    /// A beamed recipe opens in the Recipes reader. Any other page takes over the screen.
    private func showCurrentBeam() {
        guard let beam = hub.receiver.current else {
            hub.navigator.dismissBeam()
            return
        }
        if beam.payload.kind == .recipe {
            hub.navigator.openRecipe(beam.url.url, context: audience)
            hub.receiver.closeBrowser()
        } else {
            hub.navigator.presentBeam()
        }
    }

    private var slots: HubFeatureSlots {
        HubFeatureSlots(
            beam: { AnyView(HubBeamView(model: model, hub: hub)) },
            projectedApps: { AnyView(HubProjectedAppsView(client: hub.projection)) },
            people: { AnyView(PeopleSetupView(session: model.session, service: hub.faces)) },
            recognitionIndicator: {
                AnyView(RecognitionIndicatorView(service: hub.faces, session: model.session, unlock: hub.deviceUnlock))
            },
            pairing: { AnyView(PairingView(receiver: hub.receiver, session: model.session)) },
            deviceUnlock: HubDeviceUnlock(
                isOffered: { hub.deviceUnlock.isOffered },
                unlock: { await hub.deviceUnlock.unlock().unlocksPersonalContent }
            ),
            assistant: assistantSlot,
            intercom: intercomSlot,
            calendar: calendarSlot
        )
    }

    private var assistantSlot: HubAssistant {
        let engine = hub.assistant
        let navigator = hub.navigator
        return HubAssistant(
            isAvailable: { engine.isEnabled },
            overlay: { dismiss in
                AnyView(AssistantOverlayView(engine: engine, isNight: navigator.isNightMode, onDismiss: { dismiss() }))
            }
        )
    }

    /// Household notes, unless they are turned off in Settings.
    private var intercomSlot: (@MainActor () -> AnyView)? {
        guard hub.intercom.isEnabled else { return nil }
        let intercom = hub.intercom
        return { AnyView(HouseholdNoteComposer(intercom: intercom)) }
    }

    /// The Calendar a member's iPhone projects, when the person in front of the hub may see it.
    private var calendarSlot: (@MainActor () -> AnyView)? {
        guard let entry = hub.projection.entries.first(where: { $0.id.appID == BuiltInProjectedApp.calendarID }) else {
            return nil
        }
        return { AnyView(ProjectionAppView(client: hub.projection, entryID: entry.id)) }
    }

    /// The camera's estimate of the room's light, in the three steps Night Mode works with.
    static func ambientLight(isRoomDark: Bool?, brightness: Double?) -> AmbientLightHint? {
        guard let isRoomDark else { return nil }
        if isRoomDark { return .dark }
        return (brightness ?? 1) < 0.5 ? .dim : .bright
    }
}

/// The page being shown, or the recent pages when nothing is open.
private struct HubBeamView: View {
    let model: AppModel
    let hub: HubServices

    var body: some View {
        if let beam = hub.receiver.current {
            BeamBrowserView(
                receiver: hub.receiver,
                session: model.session,
                beam: beam,
                onNavigate: { [sharePlay = hub.sharePlay] url, title in
                    sharePlay.localDidNavigate(to: url, title: title)
                },
                accessory: {
                    SharePlayButton(coordinator: hub.sharePlay, url: beam.url.url, title: beam.payload.title)
                }
            )
            .id(beam.id)
        } else {
            BeamRecentsView(receiver: hub.receiver)
        }
    }
}

/// The apps a nearby iPhone projects: a grid, then the chosen app.
private struct HubProjectedAppsView: View {
    let client: ProjectionClient
    @State private var openEntry: ProjectedAppEntryID?

    var body: some View {
        Group {
            if let openEntry, client.entry(openEntry) != nil {
                ProjectionAppView(client: client, entryID: openEntry)
                    .overlay(alignment: .topLeading) {
                        Button {
                            self.openEntry = nil
                        } label: {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.title3.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .padding(12)
                        .accessibilityLabel("All iPhone apps")
                    }
            } else {
                ProjectionAppGridView(client: client) { entry in
                    client.launch(entry.id)
                    openEntry = entry.id
                }
            }
        }
        .onChange(of: client.presentationRequest != nil, initial: true) { _, requested in
            guard requested, let request = client.presentationRequest else { return }
            openEntry = request.entryID
            client.clearPresentationRequest()
        }
    }
}
