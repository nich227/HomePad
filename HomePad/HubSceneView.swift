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
            onHubSummaryChange: { [broadcaster = hub.broadcaster] summary in
                Task { await broadcaster.publish(summary) }
            },
            roleOverride: .hub
        )
        .overlay(alignment: .top) {
            VStack(spacing: 12) {
                BeamApprovalBanner(receiver: hub.receiver, proximity: model.session.proximity)
                HouseholdNoteBanner(intercom: hub.intercom, proximity: model.session.proximity)
            }
            .padding(.top, 12)
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
            messages: { AnyView(MessagesHubView(client: hub.projection, session: model.session)) },
            projectedApps: { AnyView(HubProjectedAppsView(client: hub.projection)) },
            people: { AnyView(PeopleSetupView(session: model.session, service: hub.faces)) },
            recognitionIndicator: { AnyView(RecognitionIndicatorView(service: hub.faces, session: model.session)) },
            pairing: { AnyView(PairingView(receiver: hub.receiver, session: model.session)) }
        )
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
