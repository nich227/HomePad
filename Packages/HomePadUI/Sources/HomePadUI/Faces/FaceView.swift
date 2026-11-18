import HomePadCore
import HomePadUICore
import SwiftUI

extension Date {
    /// The whole second at or before now, so one-second timelines tick on the second.
    static var startOfCurrentSecond: Date {
        Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down))
    }
}

/// Draws one face and keeps it ticking. Faces with sweeping hands or flowing shapes redraw every
/// frame unless motion is reduced; the rest redraw once a second.
struct FaceView: View {
    let kind: FaceKind
    var facePosition: (@MainActor () -> FacePosition?)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.faceDensity) private var density
    @Environment(\.hubMotion) private var motion

    private var isSmooth: Bool {
        (kind == .analog || kind == .fade || kind == .flow || kind == .memories) && !reduceMotion
    }

    var body: some View {
        Group {
            if isSmooth {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    face(at: timeline.date, sweeps: true)
                }
            } else {
                TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                    face(at: timeline.date, sweeps: false)
                }
            }
        }
        .animation(motion.gentle, value: density)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func face(at date: Date, sweeps: Bool) -> some View {
        switch kind {
        case .modular: ModularFace(date: date)
        case .photos: PhotosFace(date: date)
        case .memories: MemoriesFace(date: date)
        case .weather: WeatherFace(date: date)
        case .homeModular: HomeModularFace(date: date)
        case .calendar: CalendarFace(date: date)
        case .flow: FlowFace(date: date, facePosition: facePosition?())
        case .analog: AnalogFace(date: date, sweeps: sweeps)
        case .fade: FadeFace(date: date, sweeps: sweeps)
        case .digital: DigitalFace(date: date)
        case .homeCamera: HomeCameraFace(date: date)
        case .rainbow: RainbowFace(date: date)
        }
    }
}

extension FaceKind {
    /// The face's name in the person's language, as the hub shows it.
    public var displayName: String {
        switch self {
        case .modular: String(localized: "Modular")
        case .photos: String(localized: "Photos")
        case .memories: String(localized: "Memories")
        case .weather: String(localized: "Weather")
        case .homeModular: String(localized: "Home Modular")
        case .calendar: String(localized: "Calendar")
        case .flow: String(localized: "Flow")
        case .analog: String(localized: "Analog")
        case .fade: String(localized: "Fade")
        case .digital: String(localized: "Digital")
        case .homeCamera: String(localized: "Home Camera")
        case .rainbow: String(localized: "Rainbow")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .modular: "Modular"
        case .photos: "Photos"
        case .memories: "Memories"
        case .weather: "Weather"
        case .homeModular: "Home Modular"
        case .calendar: "Calendar"
        case .flow: "Flow"
        case .analog: "Analog"
        case .fade: "Fade"
        case .digital: "Digital"
        case .homeCamera: "Home Camera"
        case .rainbow: "Rainbow"
        }
    }
}

/// One face with sample services, for previews.
struct FacePreview: View {
    let kind: FaceKind
    let proximity: Proximity
    @State private var session: HouseholdSession
    @State private var environment = HubEnvironment.preview()

    init(_ kind: FaceKind, _ proximity: Proximity) {
        self.kind = kind
        self.proximity = proximity
        let session = HouseholdSession(store: InMemoryProfileStore(profiles: [HouseholdProfile(name: "Erica", tint: .purple)]))
        if let profile = session.profiles.first {
            session.faceRecognized(profileID: profile.id, proximity: proximity)
        }
        _session = State(initialValue: session)
    }

    var body: some View {
        GeometryReader { proxy in
            FaceView(kind: kind, facePosition: { FacePosition(x: 0.7, y: 0.4) })
                .environment(\.hubMetrics, HubMetrics(size: proxy.size))
                .environment(\.faceDensity, FaceDensity(proximity: proximity))
                .environment(environment)
                .environment(session)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

#Preview("Home Modular, near", traits: .landscapeLeft) { FacePreview(.homeModular, .near) }
#Preview("Home Modular, far", traits: .landscapeLeft) { FacePreview(.homeModular, .far) }
#Preview("Home Modular, portrait") { FacePreview(.homeModular, .mid) }
#Preview("Modular, near", traits: .landscapeLeft) { FacePreview(.modular, .near) }
#Preview("Photos, near") { FacePreview(.photos, .near) }
#Preview("Memories, near") { FacePreview(.memories, .near) }
#Preview("Weather, near", traits: .landscapeLeft) { FacePreview(.weather, .near) }
#Preview("Calendar, near", traits: .landscapeLeft) { FacePreview(.calendar, .near) }
#Preview("Flow, near", traits: .landscapeLeft) { FacePreview(.flow, .near) }
#Preview("Analog, near", traits: .landscapeLeft) { FacePreview(.analog, .near) }
#Preview("Fade, near", traits: .landscapeLeft) { FacePreview(.fade, .near) }
#Preview("Digital, far", traits: .landscapeLeft) { FacePreview(.digital, .far) }
#Preview("Home Camera, near", traits: .landscapeLeft) { FacePreview(.homeCamera, .near) }
#Preview("Rainbow, mid") { FacePreview(.rainbow, .mid) }
