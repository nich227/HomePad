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
            case .beam, .messages, .projectedApps, .people, .pairing, .settings:
                ZStack(alignment: .topLeading) {
                    Color.black
                    (slots.view(for: app) ?? AnyView(EmptyView()))
                        .padding(.top, metrics.pt(13))
                    GlassCircleButton(symbol: "xmark", label: "Close", action: onClose)
                        .padding(metrics.pt(4))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
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
                GlassCircleButton(symbol: "xmark", label: "Close", action: onClose)
                Text(title)
                    .font(.system(size: metrics.text(4.6), weight: .bold))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(metrics.pt(4))
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

struct WeatherApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 30)) { timeline in
                WeatherFace(date: timeline.date)
                    .environment(\.faceDensity, .detailed)
                    .padding(.top, metrics.pt(11))
                    .background(Color(red: 0.62, green: 0.76, blue: 0.9))
            }
            if environment.weather.error == .notConfigured {
                VStack(spacing: metrics.pt(3)) {
                    Text("To show weather, enter the hub's city and coordinates in Settings.")
                        .font(.system(size: metrics.text(3.4), weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    OpenSettingsButton()
                        .font(.system(size: metrics.text(3.2), weight: .semibold))
                        .buttonStyle(.glassProminent)
                }
                .padding(metrics.pt(5))
                .frame(maxWidth: metrics.pt(70))
                .hubTile(metrics, tint: Color.black.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            GlassCircleButton(symbol: "xmark", label: "Close", action: onClose)
                .padding(metrics.pt(4))
        }
    }
}
