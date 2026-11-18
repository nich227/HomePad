import HomePadCore
import HomePadUICore
import SwiftUI

/// Shows one app on the canvas. Native apps draw their own chrome; slot apps get a close button
/// laid over whatever their package supplies.
struct AppHostView: View {
    let app: HubApp
    let slots: HubFeatureSlots
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Group {
            switch app {
            case .clock: ClockApp(onClose: onClose)
            case .timers: TimersApp(onClose: onClose)
            case .alarms: AlarmsApp(onClose: onClose)
            case .home: HomeApp(onClose: onClose)
            case .music: MusicApp(onClose: onClose)
            case .mirror: MirrorApp(onClose: onClose)
            case .recipes: RecipesApp(onClose: onClose)
            case .weather: WeatherApp(onClose: onClose)
            case .photos: PhotosApp(onClose: onClose)
            case .beam, .projectedApps, .people, .pairing, .settings, .intercom, .calendar:
                SlotScreen(app: app, onClose: onClose) {
                    slots.view(for: app) ?? AnyView(EmptyView())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// Hosts a view from another package as an app. Those views are built from ordinary lists and
/// text styles sized for a screen in the hand, so the text is stepped up to suit the canvas,
/// and the list background is cleared so the app sits on black like the native ones.
struct SlotScreen<Content: View>: View {
    let app: HubApp
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var contentTypeSize: DynamicTypeSize {
        let steps = SlotTypeSizes.steps
        let step = SlotTextScale.step(forCanvasSide: Double(metrics.side))
        return max(dynamicTypeSize, steps[min(step, steps.count - 1)])
    }

    var body: some View {
        AppScreen(title: app.title, onClose: onClose) {
            content
                .dynamicTypeSize(contentTypeSize)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
        }
    }
}

/// The Dynamic Type sizes from Large up, in the order `SlotTextScale` counts them.
enum SlotTypeSizes {
    static let steps: [DynamicTypeSize] = [
        .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]
}

/// Common frame for native apps: a round close button, a title, and the content below.
struct AppScreen<Content: View>: View {
    let title: LocalizedStringKey
    var background: Color = .black
    var ink: Color = .white
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.pt(2)) {
            HStack(spacing: metrics.pt(3)) {
                GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
                Text(title)
                    .font(.system(size: metrics.text(4.6), weight: .bold))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, metrics.pt(4))
        .padding(.top, max(metrics.pt(4), metrics.topObstruction))
        .padding(.bottom, metrics.bottomBar)
        .background(background)
    }
}

struct ClockApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        AppScreen(title: "Clock", onClose: onClose) {
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                let time = FaceText.clock(timeline.date, calendar: calendar, density: .detailed, units: units, showsSeconds: true)
                VStack(spacing: metrics.pt(2.5)) {
                    AnalogDial(date: timeline.date, markers: .numerals, dialColor: Color(white: 0.13))
                        .frame(maxHeight: metrics.pt(46))
                    HStack(alignment: .firstTextBaseline, spacing: metrics.pt(1.2)) {
                        Text(time.digits).font(.clockDigits(size: metrics.pt(13)))
                        Text(verbatim: ":\(time.secondText ?? "")").font(.clockDigits(size: metrics.pt(6))).foregroundStyle(Color.hubSecondaryText)
                        Text(time.periodText ?? "").font(.clockDigits(size: metrics.pt(5)))
                    }
                    .foregroundStyle(.white)
                    Text(TimeTextPolicy.dateLine(for: timeline.date, style: .full, calendar: calendar, locale: locale))
                        .font(.system(size: metrics.text(3.6), weight: .semibold))
                        .foregroundStyle(Color.hubSecondaryText)
                    if let next = environment.alarms.nextAlarm(calendar: calendar) {
                        Label {
                            Text(next.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        } icon: {
                            Image(systemName: "alarm.fill")
                        }
                        .font(.system(size: metrics.text(3.2), weight: .semibold))
                        .foregroundStyle(Color(RainbowTint.orange))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The Weather face, always with its details, and a way out. When there is no weather the face
/// says why and offers Settings where that is the fix.
struct WeatherApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 30)) { timeline in
                WeatherFace(date: timeline.date)
                    .environment(\.faceDensity, .detailed)
            }
            GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
                .padding(.leading, metrics.margin)
                .padding(.top, metrics.topEdge)
        }
    }
}
