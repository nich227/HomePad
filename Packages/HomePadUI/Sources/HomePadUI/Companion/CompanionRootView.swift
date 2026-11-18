import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadUICore
import SwiftUI

/// The iPhone side: what the hub is showing, the beam slot, projected apps, and, while setup
/// mode is on, people and pairing.
public struct CompanionRootView: View {
    private enum Tab: Hashable {
        case hub, beam, apps, people
    }

    private let session: HouseholdSession
    private let settings: HomePadSettings
    private let slots: HubFeatureSlots
    private let hubSummary: HubStatusSummary?
    @State private var tab = Tab.hub

    /// - Parameter hubSummary: The latest summary received from the hub, or nil when none has
    ///   arrived. `HubSummaryReceiver` keeps one up to date from a peer channel.
    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        slots: HubFeatureSlots = HubFeatureSlots(),
        hubSummary: HubStatusSummary? = nil
    ) {
        self.session = session
        self.settings = settings
        self.slots = slots
        self.hubSummary = hubSummary
    }

    public var body: some View {
        let setupMode = settings[GeneralSettings.setupMode]
        TabView(selection: $tab) {
            SwiftUI.Tab("Hub", systemImage: "square.fill", value: Tab.hub) {
                NavigationStack {
                    HubSummaryView(summary: hubSummary)
                        .navigationTitle("HomePad")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                slots.recognitionIndicator()
                            }
                        }
                }
            }
            SwiftUI.Tab("Beam", systemImage: "dot.radiowaves.left.and.right", value: Tab.beam) {
                slots.beam()
            }
            SwiftUI.Tab("Apps", systemImage: "square.grid.2x2.fill", value: Tab.apps) {
                slots.projectedApps()
            }
            SwiftUI.Tab("People", systemImage: "person.2.fill", value: Tab.people) {
                NavigationStack {
                    people(setupMode: setupMode)
                        .navigationTitle("People")
                }
            }
        }
        .environment(session)
    }

    @ViewBuilder
    private func people(setupMode: Bool) -> some View {
        if setupMode {
            List {
                Section("Household") {
                    slots.people()
                        .frame(minHeight: 320)
                        .listRowInsets(EdgeInsets())
                }
                Section("This iPhone") {
                    slots.pairing()
                        .frame(minHeight: 320)
                        .listRowInsets(EdgeInsets())
                }
            }
        } else {
            ContentUnavailableView {
                Label(session.profiles.isEmpty ? "No One Is Set Up" : "Setup Is Off", systemImage: "person.2.slash")
            } description: {
                Text("To add people, enroll faces, or pair this iPhone, turn on Setup Mode in Settings.")
            } actions: {
                OpenSettingsButton()
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A short, glanceable account of the hub's screen.
struct HubSummaryView: View {
    let summary: HubStatusSummary?

    var body: some View {
        TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
            if let summary, summary.isFresh(at: timeline.date) {
                List {
                    Section("On the Hub") {
                        row("Showing", systemImage: "rectangle.on.rectangle", value: showing(summary))
                        row("In front", systemImage: "person.fill", value: summary.profileName.map { Text(verbatim: $0) } ?? Text("Guest"))
                        if summary.isNight {
                            row("Night mode", systemImage: "moon.fill", value: Text("On"))
                        }
                    }
                    if summary.runningTimers > 0, let end = summary.nextTimerEnd {
                        Section("Timers") {
                            row("Running", systemImage: "timer", value: Text(verbatim: "\(summary.runningTimers)"))
                            row("Next ends in", systemImage: "hourglass", value: Text(DurationText.countdown(end.timeIntervalSince(timeline.date))).monospacedDigit())
                        }
                    }
                    if let title = summary.nowPlayingTitle {
                        Section("Now Playing") {
                            row("Song", systemImage: "music.note", value: Text(verbatim: title))
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    VStack {
                        HomePadAnimationView(.pairing, loop: true)
                            .frame(width: 140, height: 140)
                        Text("Hub Not Reachable")
                    }
                } description: {
                    Text("Open HomePad on the iPad and keep this iPhone nearby.")
                }
            }
        }
    }

    private func showing(_ summary: HubStatusSummary) -> Text {
        if let app = summary.app { return Text(app.title) }
        if summary.showsHomeScreen { return Text("Home Screen") }
        return Text("\(Text(summary.face.title)) face")
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, value: Text) -> some View {
        LabeledContent {
            value
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview("Companion") {
    let session = HouseholdSession(store: InMemoryProfileStore(profiles: [HouseholdProfile(name: "Erica", tint: .purple)]))
    return CompanionRootView(
        session: session,
        settings: HomePadSettings(),
        hubSummary: HubStatusSummary(surface: .faces, face: .flow, profileName: "Erica", timers: [], nowPlaying: nil, isNight: false, at: Date())
    )
}
