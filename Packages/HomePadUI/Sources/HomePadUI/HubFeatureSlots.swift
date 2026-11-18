import HomePadAnimations
import HomePadAnimationsCore
import HomePadUICore
import SwiftUI

/// The device's own biometrics (Touch ID) as a second step after a camera match that could not
/// prove a live face. The camera picks who; this unlocks that member's personal content.
public struct HubDeviceUnlock {
    /// Whether to show the unlock affordance right now.
    public var isOffered: @MainActor () -> Bool
    /// Runs the biometric check. True when personal content is now unlocked.
    public var unlock: @MainActor () async -> Bool

    public init(isOffered: @escaping @MainActor () -> Bool, unlock: @escaping @MainActor () async -> Bool) {
        self.isOffered = isOffered
        self.unlock = unlock
    }
}

/// An assistant another package supplies. The hub gives it a control to open it and the whole
/// screen to draw on; what it shows and does is its own.
public struct HubAssistant {
    /// Whether the assistant can be opened right now. The hub shows its control only then.
    public var isAvailable: @MainActor () -> Bool
    /// The assistant's view, drawn over everything. Call `dismiss` to close it.
    public var overlay: @MainActor (_ dismiss: @escaping @MainActor () -> Void) -> AnyView

    public init(
        isAvailable: @escaping @MainActor () -> Bool,
        overlay: @escaping @MainActor (_ dismiss: @escaping @MainActor () -> Void) -> AnyView
    ) {
        self.isAvailable = isAvailable
        self.overlay = overlay
    }
}

/// Views supplied by the other feature packages. The app target fills these in; each has a
/// placeholder so the shell runs on its own.
@MainActor
public struct HubFeatureSlots {
    /// The beam inbox and browser.
    public var beam: @MainActor () -> AnyView
    /// Apps projected from a nearby iPhone.
    public var projectedApps: @MainActor () -> AnyView
    /// Profiles and face enrollment. Shown only while setup mode is on.
    public var people: @MainActor () -> AnyView
    /// A small status chip drawn next to the profile avatar.
    public var recognitionIndicator: @MainActor () -> AnyView
    /// Pairing an iPhone. Shown only while setup mode is on.
    public var pairing: @MainActor () -> AnyView
    /// Nil when the device has no biometrics to offer. The shell then behaves as it does for
    /// any locked member.
    public var deviceUnlock: HubDeviceUnlock?
    /// Nil when no assistant is built in.
    public var assistant: HubAssistant?
    /// Household notes. Nil leaves the Intercom icon and control out.
    public var intercom: (@MainActor () -> AnyView)?
    /// A calendar projected from a member's iPhone. Nil leaves the Calendar icon out.
    public var calendar: (@MainActor () -> AnyView)?
    /// Live things from other packages for the pill at the top of a face: a household note, an
    /// incoming page. Mark anything personal so guests never see it.
    public var liveItems: @MainActor () -> [LivePillItem]

    public init(
        beam: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.beam) },
        projectedApps: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.projectedApps) },
        people: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.people) },
        recognitionIndicator: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) },
        pairing: @escaping @MainActor () -> AnyView = { HubFeatureSlots.placeholder(.pairing) },
        deviceUnlock: HubDeviceUnlock? = nil,
        assistant: HubAssistant? = nil,
        intercom: (@MainActor () -> AnyView)? = nil,
        calendar: (@MainActor () -> AnyView)? = nil,
        liveItems: @escaping @MainActor () -> [LivePillItem] = { [] }
    ) {
        self.beam = beam
        self.projectedApps = projectedApps
        self.people = people
        self.recognitionIndicator = recognitionIndicator
        self.pairing = pairing
        self.deviceUnlock = deviceUnlock
        self.assistant = assistant
        self.intercom = intercom
        self.calendar = calendar
        self.liveItems = liveItems
    }

    /// The optional apps that have something behind them right now.
    var availableApps: Set<HubApp> {
        var apps = Set<HubApp>()
        if intercom != nil { apps.insert(.intercom) }
        if calendar != nil { apps.insert(.calendar) }
        return apps
    }

    func view(for app: HubApp) -> AnyView? {
        switch app {
        case .beam: beam()
        case .projectedApps: projectedApps()
        case .people: people()
        case .pairing: pairing()
        case .intercom: intercom?()
        case .calendar: calendar?()
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
    /// The app's name in the person's language, as it is under its icon.
    public var displayName: String {
        switch self {
        case .clock: String(localized: "Clock")
        case .timers: String(localized: "Timers")
        case .alarms: String(localized: "Alarms")
        case .home: String(localized: "Home")
        case .music: String(localized: "Music")
        case .mirror: String(localized: "Mirror")
        case .recipes: String(localized: "Recipes")
        case .weather: String(localized: "Weather")
        case .photos: String(localized: "Photos")
        case .beam: String(localized: "Beam")
        case .projectedApps: String(localized: "iPhone Apps")
        case .people: String(localized: "People")
        case .pairing: String(localized: "Pairing")
        case .settings: String(localized: "Settings")
        case .intercom: String(localized: "Intercom")
        case .calendar: String(localized: "Calendar")
        }
    }

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
        case .projectedApps: "iPhone Apps"
        case .people: "People"
        case .pairing: "Pairing"
        case .settings: "Settings"
        case .intercom: "Intercom"
        case .calendar: "Calendar"
        }
    }
}

extension HubScreen {
    /// The name of what is in front. Names a kind of screen, never what is on it.
    var title: String {
        switch self {
        case .face(let kind): kind?.displayName ?? String(localized: "Face")
        case .homeScreen: String(localized: "Home Screen")
        case .app(let app): app.displayName
        case .takeover: HubApp.beam.displayName
        case .overlay(.controlCenter): String(localized: "Control Center")
        case .overlay(.facePicker): String(localized: "Faces")
        case .overlay(.assistant): String(localized: "Assistant")
        case .overlay(.inlineControl(.thermostat)): String(localized: "Thermostat")
        case .overlay(.inlineControl(.dimmer)): String(localized: "Light")
        case .overlay(.inlineControl(.camera)): String(localized: "Camera")
        }
    }
}
