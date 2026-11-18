import HomePadBeam
import HomePadCore
import HomePadMessaging
import HomePadMessagingCore
import HomePadUI
import SwiftUI

/// The iPhone side: beam pages to the hub, see what is projected, and pair.
struct CompanionSceneView: View {
    let model: AppModel
    let companion: CompanionServices

    var body: some View {
        HomePadRootView(
            session: model.session,
            settings: model.settings,
            slots: slots,
            environment: .preview(runningTimer: false),
            navigator: HubNavigator(),
            hubSummary: companion.summary.summary,
            roleOverride: .companion
        )
        .homePadReplyComposer(host: companion.host)
        .beamPairingLinkHandler(companion.sender)
        .task {
            _ = await companion.notifier.requestAuthorization()
        }
    }

    private var slots: HubFeatureSlots {
        HubFeatureSlots(
            beam: { AnyView(CompanionBeamView(companion: companion)) },
            projectedApps: { AnyView(CompanionAppsView(companion: companion)) },
            people: {
                AnyView(ContentUnavailableView(
                    "People Live on the Hub",
                    systemImage: "person.2.fill",
                    description: Text("Add household members and enroll faces in HomePad on the iPad.")
                ))
            },
            pairing: {
                AnyView(ContentUnavailableView(
                    "Pair from the Beam Tab",
                    systemImage: "qrcode.viewfinder",
                    description: Text("Open Pairing in HomePad on the iPad, then scan the code from the Beam tab here.")
                ))
            }
        )
    }
}

private struct CompanionBeamView: View {
    let companion: CompanionServices

    var body: some View {
        if companion.sharePlay.isActive {
            SharedPageView(coordinator: companion.sharePlay)
        } else {
            BeamComposerView(sender: companion.sender) { url in
                SharePlayButton(coordinator: companion.sharePlay, url: url, title: nil)
            }
        }
    }
}

/// What this iPhone shows on the hub, the message relay guide, and household notes.
private struct CompanionAppsView: View {
    let companion: CompanionServices

    var body: some View {
        NavigationStack {
            List {
                Section("Shown on the Hub") {
                    if companion.host.projectedApps.isEmpty {
                        Text("Nothing is being shown. Turn apps on in Settings.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(companion.host.projectedApps, id: \.id) { app in
                        Label(app.name, systemImage: app.symbolName)
                    }
                }
                Section("Messages") {
                    NavigationLink("Set Up Message Relay") {
                        ShortcutsSetupGuideView()
                    }
                }
                Section("Household Note") {
                    HouseholdNoteComposer(intercom: companion.intercom)
                }
            }
            .navigationTitle("iPhone Apps")
        }
    }
}
