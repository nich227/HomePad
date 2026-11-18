import HomePadCore
import HomePadUICore
import SwiftUI

/// A two by two widget tile on the Home Screen. Personal widgets are drawn greyed out with no
/// detail until personal content is unlocked.
struct HomeWidgetView: View {
    let kind: HubWidgetKind
    let isRedacted: Bool
    /// The widget is locked, and tapping it asks for the device's biometrics.
    var offersUnlock = false
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @State private var isOnScreen = false

    var body: some View {
        Button(action: action) {
            Group {
                if isRedacted, offersUnlock {
                    unlockPrompt
                } else if isRedacted {
                    redacted
                } else {
                    WidgetContent(kind: kind, isInUse: isOnScreen)
                }
            }
            .padding(metrics.pt(3.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRedacted && !offersUnlock)
        .hubTile(metrics, tint: Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
        .hoverEffect(.highlight)
        .padding(.bottom, metrics.text(2))
        .onScrollVisibilityChange(threshold: 0.4) { isOnScreen = $0 }
        .accessibilityIdentifier("widget.\(kind.rawValue)")
    }

    /// A locked personal widget while Touch ID is offered: the whole tile is the button.
    private var unlockPrompt: some View {
        VStack(spacing: metrics.pt(1.6)) {
            Label(kind.title, systemImage: "lock.fill")
                .font(.system(size: metrics.text(2.8), weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Image(systemName: "touchid")
                .font(.system(size: metrics.pt(13), weight: .regular))
                .foregroundStyle(Color(RainbowTint.red))
            Text("Unlock with Touch ID")
                .font(.system(size: metrics.text(3.1), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private var redacted: some View {
        VStack(alignment: .leading, spacing: metrics.pt(2)) {
            Label(kind.title, systemImage: "lock.fill")
                .font(.system(size: metrics.text(3), weight: .semibold))
            RoundedRectangle(cornerRadius: metrics.pt(1)).frame(height: metrics.pt(3.2))
            RoundedRectangle(cornerRadius: metrics.pt(1)).frame(width: metrics.pt(20), height: metrics.pt(3.2))
            RoundedRectangle(cornerRadius: metrics.pt(1)).frame(width: metrics.pt(14), height: metrics.pt(3.2))
        }
        .foregroundStyle(.white.opacity(0.28))
        .accessibilityElement()
        .accessibilityLabel(kind.title)
        .accessibilityHint("Locked until the hub recognizes its owner.")
    }
}

extension HubWidgetKind {
    var title: LocalizedStringKey {
        switch self {
        case .clock: "Clock"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .timers: "Timers"
        case .nextAlarm: "Next Alarm"
        case .nowPlaying: "Now Playing"
        case .home: "Home"
        case .thermostat: "Thermostat"
        case .camera: "Camera"
        case .photo: "Photo"
        }
    }
}

/// The inside of a widget. Also used by the second column in the fill layout.
struct WidgetContent: View {
    let kind: HubWidgetKind
    /// Whether the widget is in view. Its service starts, and may ask for access, only then.
    var isInUse = true
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        switch kind {
        case .clock:
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                AnalogDial(date: timeline.date, markers: .numerals, dialColor: Color.white.opacity(0.08))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .calendar:
            TimelineView(.everyMinute) { timeline in
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeline.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: metrics.text(3.4), weight: .semibold))
                        .foregroundStyle(Color(RainbowTint.red))
                    Text(timeline.date, format: .dateTime.day())
                        .font(.system(size: metrics.pt(20), weight: .medium))
                        .foregroundStyle(.white)
                    Text(timeline.date, format: .dateTime.month(.wide))
                        .font(.system(size: metrics.text(3)))
                        .foregroundStyle(Color.hubSecondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        case .weather:
            weather
        case .timers:
            timers
        case .nextAlarm:
            nextAlarm
        case .nowPlaying:
            nowPlaying
        case .home:
            home
        case .thermostat:
            thermostat
        case .camera:
            camera
        case .photo:
            photo
        }
    }

    private func heading(_ title: LocalizedStringKey, symbol: String) -> some View {
        heading(Text(title), symbol: symbol)
    }

    private func heading(_ title: Text, symbol: String) -> some View {
        Label { title } icon: { Image(systemName: symbol) }
            .font(.system(size: metrics.text(3), weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }

    private var weather: some View {
        let snapshot = environment.weather.snapshot
        return VStack(alignment: .leading, spacing: metrics.pt(0.6)) {
            heading(snapshot.flatMap { $0.locationName.isEmpty ? nil : Text(verbatim: $0.locationName) } ?? Text("Weather"), symbol: snapshot?.symbolName ?? "cloud.fill")
            if let snapshot {
                Text(units.degrees(snapshot.temperatureCelsius))
                    .font(.system(size: metrics.pt(13), weight: .regular))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: metrics.pt(11)))
                    .padding(.top, metrics.pt(2))
            }
            Spacer(minLength: 0)
            if let snapshot {
                Text(snapshot.conditionText)
                Text("H:\(units.degrees(snapshot.highCelsius)) L:\(units.degrees(snapshot.lowCelsius))")
            } else {
                Text(WeatherMessage(problem: environment.weather.problem).title)
            }
        }
        .font(.system(size: metrics.text(2.9), weight: .medium))
        .foregroundStyle(Color.hubSecondaryText)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .startsOnFirstUse(when: isInUse) { environment.weather.begin() }
    }

    private var timers: some View {
        let strip = environment.timers.strip
        return VStack(alignment: .leading, spacing: metrics.pt(1.4)) {
            heading("Timers", symbol: "timer")
            if strip.entries.isEmpty {
                TimerRingView(progress: 1, count: 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        Text("No Timers")
                            .font(.system(size: metrics.text(3), weight: .semibold))
                            .foregroundStyle(Color.hubSecondaryText)
                    )
            } else {
                TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: metrics.pt(1)) {
                        ForEach(environment.timers.strip.entries) { entry in
                            HStack {
                                Text(entry.name.isEmpty ? String(localized: "Timer") : entry.name)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(entry.countdown)
                                    .monospacedDigit()
                                    .foregroundStyle(entry.isPaused ? Color.hubSecondaryText : Color(RainbowTint.orange))
                            }
                            .font(.system(size: metrics.text(3.6), weight: .semibold))
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var nextAlarm: some View {
        let next = environment.alarms.nextAlarm(calendar: calendar)
        return VStack(alignment: .leading, spacing: metrics.pt(1)) {
            heading("Next Alarm", symbol: "alarm.fill")
            Spacer(minLength: 0)
            Text(next.map { $0.date.formatted(date: .omitted, time: .shortened) } ?? String(localized: "None"))
                .font(.system(size: metrics.pt(8), weight: .medium))
                .foregroundStyle(.white)
            Text(next?.alarm.label ?? "")
                .font(.system(size: metrics.text(2.9)))
                .foregroundStyle(Color.hubSecondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    private var nowPlaying: some View {
        let playing = environment.music.nowPlaying
        return VStack(alignment: .leading, spacing: metrics.pt(1.2)) {
            HStack(alignment: .top) {
                ArtworkView(image: environment.music.artwork, cornerRadius: metrics.pt(1.6))
                    .frame(width: metrics.pt(15), height: metrics.pt(15))
                Spacer()
                Button {
                    environment.music.togglePlayPause()
                } label: {
                    Image(systemName: playing?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: metrics.pt(5)))
                        .foregroundStyle(.white)
                        .frame(width: metrics.pt(9), height: metrics.pt(9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing?.isPlaying == true ? Text("Pause") : Text("Play"))
            }
            Spacer(minLength: 0)
            Text(playing?.title ?? String(localized: "Not Playing"))
                .font(.system(size: metrics.text(3.3), weight: .semibold))
                .foregroundStyle(.white)
            Text(playing?.artist ?? "")
                .font(.system(size: metrics.text(2.9)))
                .foregroundStyle(Color.hubSecondaryText)
        }
        .lineLimit(1)
        .startsOnFirstUse(when: isInUse) { environment.music.start() }
    }

    private var home: some View {
        let snapshot = environment.home.snapshot
        let lightsOn = snapshot.accessories.filter { $0.kind == .light && $0.isOn }.count
        return VStack(alignment: .leading, spacing: metrics.pt(1.2)) {
            heading("Home", symbol: "house.fill")
            Spacer(minLength: 0)
            if environment.home.access == .ready {
                Text("\(lightsOn) lights on")
                    .font(.system(size: metrics.text(4), weight: .semibold))
                    .foregroundStyle(.white)
                Text(snapshot.homeName)
                    .font(.system(size: metrics.text(2.9)))
                    .foregroundStyle(Color.hubSecondaryText)
            } else {
                Text("Not set up")
                    .font(.system(size: metrics.text(3.4), weight: .semibold))
                    .foregroundStyle(Color.hubSecondaryText)
            }
        }
        .lineLimit(1)
        .startsOnFirstUse(when: isInUse) { environment.home.start() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thermostat: some View {
        if let thermostat = environment.home.snapshot.thermostats.first {
            VStack(alignment: .leading, spacing: 0) {
                heading("Thermostat", symbol: "thermometer.medium")
                Text(units.degrees(thermostat.targetCelsius))
                    .font(.system(size: metrics.pt(15), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(verbatim: "\(thermostat.roomName) \u{00B7} \(units.degrees(thermostat.currentCelsius))")
                    .font(.system(size: metrics.text(2.9)))
                    .foregroundStyle(Color.hubSecondaryText)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        } else {
            heading("Thermostat", symbol: "thermometer.medium")
        }
    }

    @ViewBuilder
    private var camera: some View {
        if let camera = environment.home.snapshot.cameras.first {
            environment.home.cameraView(id: camera.id, live: false)
                .padding(-metrics.pt(3.4))
                .accessibilityLabel(Text(camera.name))
        } else {
            heading("Camera", symbol: "video.fill")
        }
    }

    @ViewBuilder
    private var photo: some View {
        let photos = environment.photos.picked
        if let index = PhotoRotation.index(count: photos.count, at: Date(), shuffleMinutes: 5) {
            Image(uiImage: photos[index].image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(-metrics.pt(3.4))
                .accessibilityLabel("Photo")
        } else {
            heading("Photo", symbol: "photo.fill")
        }
    }
}
