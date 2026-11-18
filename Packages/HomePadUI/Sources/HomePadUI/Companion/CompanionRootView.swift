import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadUICore
import SwiftUI

/// The companion: what the hub is showing, the beam slot, projected apps, and, while setup mode
/// is on, people and pairing. In a compact width each is a tab. In a regular width, such as the
/// inner display of a folding iPhone or an iPad, the hub's status and the list of sections stay
/// on the leading side and the chosen section sits beside them.
public struct CompanionRootView: View {
    private let session: HouseholdSession
    private let settings: HomePadSettings
    private let slots: HubFeatureSlots
    private let hubSummary: HubStatusSummary?
    /// One selection for both arrangements, so folding and unfolding keep the place.
    @State private var selection = CompanionSection.hub
    @State private var width: CGFloat?
    /// The person may hide the leading column. Where the system lays it over the content, in
    /// a narrow space, that is how they get it out of the way.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
        // A UI test may ask for a sample summary, since no hub is running beside it.
        self.hubSummary = hubSummary ?? (HubTestHooks.current.usesSampleData ? SampleContent.hubSummary : nil)
    }

    public var body: some View {
        let arrangement = CompanionLayoutPolicy.arrangement(
            isRegularWidth: horizontalSizeClass == .regular,
            width: Double(width ?? .infinity)
        )
        Group {
            switch arrangement {
            case .tabs: tabs
            case .twoColumn: columns
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(session)
    }

    // MARK: Compact width

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(CompanionSection.allCases) { section in
                SwiftUI.Tab(section.title, systemImage: section.symbol, value: section) {
                    content(of: section)
                }
            }
        }
    }

    // MARK: Regular width

    /// A split view adapts to a fold on its own: each column takes one side of it.
    private var columns: some View {
        let sidebarWidth = CGFloat(CompanionLayoutPolicy.sidebarWidth(forWidth: Double(width ?? .infinity)))
        let range = CompanionLayoutPolicy.sidebarWidthRange
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                List(selection: sidebarSelection) {
                    if let hubSummary, hubSummary.isFresh(at: timeline.date) {
                        HubSummarySections(summary: hubSummary, now: timeline.date)
                            .selectionDisabled()
                    } else {
                        Section("On the Hub") {
                            Label {
                                Text("Hub Not Reachable")
                                Text("Open HomePad on the iPad and keep this iPhone nearby.")
                            } icon: {
                                Image(systemName: "wifi.slash")
                            }
                            .selectionDisabled()
                        }
                    }
                    Section {
                        ForEach(CompanionLayoutPolicy.sidebarSections) { section in
                            Label(section.title, systemImage: section.symbol)
                                .tag(section)
                                .accessibilityIdentifier("companion.section.\(section.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("HomePad")
            .navigationSplitViewColumnWidth(min: CGFloat(range.lowerBound), ideal: sidebarWidth, max: CGFloat(range.upperBound))
        } detail: {
            content(of: CompanionLayoutPolicy.detail(for: selection))
                .navigationSplitViewColumnWidth(min: CGFloat(CompanionLayoutPolicy.minimumDetailWidth), ideal: max(CGFloat(CompanionLayoutPolicy.minimumDetailWidth), (width ?? 900) - sidebarWidth))
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<CompanionSection?> {
        Binding(
            get: { CompanionLayoutPolicy.detail(for: selection) },
            set: { chosen in
                if let chosen {
                    selection = chosen
                }
            }
        )
    }

    // MARK: Sections

    /// The same view in a tab and in the trailing column.
    @ViewBuilder
    private func content(of section: CompanionSection) -> some View {
        switch section {
        case .hub:
            NavigationStack {
                HubSummaryView(summary: hubSummary)
                    .navigationTitle("HomePad")
            }
        case .beam:
            // The beam view sets a title and expects a navigation stack around it.
            NavigationStack {
                slots.beam()
            }
        case .apps:
            slots.projectedApps()
        case .people:
            NavigationStack {
                people(setupMode: settings[GeneralSettings.setupMode])
                    .navigationTitle("People")
            }
        }
    }

    @ViewBuilder
    private func people(setupMode: Bool) -> some View {
        if setupMode {
            List {
                Section("Household") {
                    slots.people()
                        .frame(maxWidth: .infinity, minHeight: 240)
                        .listRowInsets(EdgeInsets())
                }
                Section("This iPhone") {
                    slots.pairing()
                        .frame(maxWidth: .infinity, minHeight: 240)
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

extension CompanionSection {
    var title: LocalizedStringKey {
        switch self {
        case .hub: "Hub"
        case .beam: "Beam"
        case .apps: "Apps"
        case .people: "People"
        }
    }

    var symbol: String {
        switch self {
        case .hub: "square.fill"
        case .beam: "dot.radiowaves.left.and.right"
        case .apps: "square.grid.2x2.fill"
        case .people: "person.2.fill"
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
                    HubSummarySections(summary: summary, now: timeline.date)
                }
            } else {
                ContentUnavailableView {
                    VStack(spacing: 20) {
                        // The animation is drawn in white for the hub's black canvas, so it
                        // sits on a small black square shaped like that canvas.
                        HomePadAnimationView(.pairing, loop: true)
                            .frame(width: 120, height: 120)
                            .padding(20)
                            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(.black))
                            .accessibilityHidden(true)
                        Text("Hub Not Reachable")
                    }
                } description: {
                    Text("Open HomePad on the iPad and keep this iPhone nearby.")
                }
            }
        }
    }
}

/// The rows that describe the hub, for a list in a tab or in the leading column.
struct HubSummarySections: View {
    let summary: HubStatusSummary
    let now: Date

    var body: some View {
        Section("On the Hub") {
            row("Showing", systemImage: "rectangle.on.rectangle", value: showing)
            row("In front", systemImage: "person.fill", value: summary.profileName.map { Text(verbatim: $0) } ?? Text("Guest"))
            if summary.isNight {
                row("Night mode", systemImage: "moon.fill", value: Text("On"))
            }
        }
        if summary.runningTimers > 0, let end = summary.nextTimerEnd {
            Section("Timers") {
                row("Running", systemImage: "timer", value: Text(verbatim: "\(summary.runningTimers)"))
                row("Next ends in", systemImage: "hourglass", value: Text(DurationText.countdown(end.timeIntervalSince(now))).monospacedDigit())
            }
        }
        if let title = summary.nowPlayingTitle {
            Section("Now Playing") {
                row("Song", systemImage: "music.note", value: Text(verbatim: title))
            }
        }
    }

    private var showing: Text {
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
