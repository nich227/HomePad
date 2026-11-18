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

    private var isSmooth: Bool {
        (kind == .analog || kind == .fade || kind == .flow) && !reduceMotion
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
        .animation(.smooth(duration: 0.55), value: density)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func face(at date: Date, sweeps: Bool) -> some View {
        switch kind {
        case .modular: ModularFace(date: date)
        case .photos: PhotosFace(date: date)
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
    var title: LocalizedStringKey {
        switch self {
        case .modular: "Modular"
        case .photos: "Photos"
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

/// One face on a square canvas with sample services, for previews.
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
            let side = min(proxy.size.width, proxy.size.height)
            FaceView(kind: kind, facePosition: { FacePosition(x: 0.7, y: 0.4) })
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * CGFloat(CanvasLayout.cornerRadiusFraction), style: .continuous))
                .environment(\.hubMetrics, HubMetrics(side: side))
                .environment(\.faceDensity, FaceDensity(proximity: proximity))
                .environment(environment)
                .environment(session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }
}

#Preview("Modular, far") { FacePreview(.modular, .far) }
#Preview("Modular, near") { FacePreview(.modular, .near) }
#Preview("Photos, far") { FacePreview(.photos, .far) }
#Preview("Photos, near") { FacePreview(.photos, .near) }
#Preview("Weather, far") { FacePreview(.weather, .far) }
#Preview("Weather, near") { FacePreview(.weather, .near) }
#Preview("Home Modular, far") { FacePreview(.homeModular, .far) }
#Preview("Home Modular, near") { FacePreview(.homeModular, .near) }
#Preview("Calendar, far") { FacePreview(.calendar, .far) }
#Preview("Calendar, near") { FacePreview(.calendar, .near) }
#Preview("Flow, far") { FacePreview(.flow, .far) }
#Preview("Flow, near") { FacePreview(.flow, .near) }
#Preview("Analog, far") { FacePreview(.analog, .far) }
#Preview("Analog, near") { FacePreview(.analog, .near) }
#Preview("Fade, far") { FacePreview(.fade, .far) }
#Preview("Fade, near") { FacePreview(.fade, .near) }
#Preview("Digital, far") { FacePreview(.digital, .far) }
#Preview("Digital, near") { FacePreview(.digital, .near) }
#Preview("Home Camera, far") { FacePreview(.homeCamera, .far) }
#Preview("Home Camera, near") { FacePreview(.homeCamera, .near) }
#Preview("Rainbow, far") { FacePreview(.rainbow, .far) }
#Preview("Rainbow, near") { FacePreview(.rainbow, .near) }
