import HomePadAnimations
import HomePadAnimationsCore
import HomePadUICore
import SwiftUI

/// Views supplied by the other feature packages. The app target fills these in; each has a
/// placeholder so the shell runs on its own.
@MainActor
public struct HubFeatureSlots {
    /// The beam inbox and browser.
    public var beam: @MainActor () -> AnyView
    public var messages: @MainActor () -> AnyView
    /// Apps projected from a nearby iPhone.
    public var projectedApps: @MainActor () -> AnyView
    /// Profiles and face enrollment. Shown only while setup mode is on.
    public var people: @MainActor () -> AnyView
    /// A small status chip drawn next to the profile avatar.
    public var recognitionIndicator: @MainActor () -> AnyView
    /// Pairing an iPhone. Shown only while setup mode is on.
    public var pairing: @MainActor () -> AnyView

    public init(
        beam: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.beam) },
        messages: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.messages) },
        projectedApps: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.projectedApps) },
        people: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.people) },
        recognitionIndicator: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) },
        pairing: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.pairing) }
    ) {
        self.beam = beam
        self.messages = messages
        self.projectedApps = projectedApps
        self.people = people
        self.recognitionIndicator = recognitionIndicator
        self.pairing = pairing
    }

    func view(for app: HubApp) -> AnyView? {
        switch app {
        case .beam: beam()
        case .messages: messages()
        case .projectedApps: projectedApps()
        case .people: people()
        case .pairing: pairing()
        default: nil
        }
    }

    /// What a slot shows until its package is wired in.
    public static func placeholder(_ app: HubApp) -> AnyView {
        AnyView(SlotPlaceholderView(app: app))
    }
}

struct SlotPlaceholderView: View {
    let app: HubApp

    private var animation: HomePadAnimation {
        switch app {
        case .beam: .beamIncoming
        case .people: .faceScan
        case .pairing, .projectedApps: .pairing
        default: .listening
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HomePadAnimationView(animation, loop: true)
                .frame(width: 160, height: 160)
            Text(app.title)
                .font(.title2.weight(.semibold))
            Text("Nothing here yet.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension HubApp {
    var title: LocalizedStringKey {
        switch self {
        case .clock: "Clock"
        case .timers: "Timers"
        case .alarms: "Alarms"
        case .home: "Home"
        case .music: "Music"
        case .mirror: "Mirror"
        case .recipes: "Recipes"
        case .weather: "Weather"
        case .photos: "Photos"
        case .beam: "Beam"
        case .messages: "Messages"
        case .projectedApps: "iPhone Apps"
        case .people: "People"
        case .pairing: "Pairing"
        case .settings: "Settings"
        }
    }
}
