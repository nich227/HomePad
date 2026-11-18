import HomePadCore
import HomePadUICore
import SwiftUI

/// A few large widgets with their backgrounds stripped away, on pure black: the date, an analog
/// clock, the weather, and what is live. Two by two on a square, with a third column or row
/// where the screen has room. From across the room the small print fades and the numbers stay.
struct ModularFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session

    private var accent: Color {
        session.activeProfile.map { Color($0.tint) } ?? Color(red: 1, green: 0.42, blue: 0.36)
    }

    var body: some View {
        let board = metrics.boardSize
        let grid = ModularLayout.grid(width: Double(board.width), height: Double(board.height))
        let widgets = ModularLayout.widgets(for: grid)
        let placements = TileGridPacker.pack(Array(repeating: .single, count: widgets.count), in: grid)
        ZStack {
            Color.black
            TileBoard(grid: grid, gap: metrics.gutter * 2) {
                ForEach(Array(zip(widgets, placements)), id: \.0) { widget, placement in
                    if let placement {
                        view(for: widget)
                            .padding(metrics.token(10))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .tile(placement)
                    }
                }
            }
            .frame(width: board.width, height: board.height)
            .padding(metrics.boardInsets)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func view(for widget: ModularLayout.Widget) -> some View {
        switch widget {
        case .date: dateWidget
        case .clock:
            AnalogDial(date: date, markers: .numerals, dialColor: Color(white: 0.13), secondColor: accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .weather: weatherWidget
        case .nowPlaying: musicWidget
        case .home: homeWidget
        case .timers: timersWidget
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
            .foregroundStyle(Color.hubSecondaryText)
            .opacity(density.showsLabels ? 1 : 0)
    }

    private func hero(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.token(DesignTokens.hero(for: density) * 1.25), weight: .semibold).width(.condensed))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }

    private var dateWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.token(6)) {
                Text(date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(accent)
                Text(date, format: .dateTime.month(.abbreviated)).foregroundStyle(.white)
            }
            .font(.system(size: metrics.textToken(30), weight: .semibold))
            hero(date.formatted(.dateTime.day()))
        }
        .accessibilityElement(children: .combine)
    }

    private var weatherWidget: some View {
        let weather = environment.weather.snapshot
        return VStack(alignment: .leading, spacing: metrics.token(2)) {
            HStack(spacing: metrics.token(6)) {
                Image(systemName: weather?.symbolName ?? "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                Text(weather?.locationName ?? String(localized: "Weather"))
            }
            .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
            .foregroundStyle(.white)
            if let weather {
                hero(units.degrees(weather.temperatureCelsius))
                caption(weather.conditionText)
                caption("H:\(units.degrees(weather.highCelsius)) L:\(units.degrees(weather.lowCelsius))")
            } else {
                caption(WeatherMessage(problem: environment.weather.problem).title)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .startsOnFirstUse { environment.weather.begin() }
    }

    private var musicWidget: some View {
        let playing = environment.music.nowPlaying
        return VStack(alignment: .leading, spacing: metrics.token(6)) {
            ArtworkView(image: environment.music.artwork, cornerRadius: metrics.token(10))
                .frame(width: metrics.token(84), height: metrics.token(84))
            Text(playing?.title ?? String(localized: "Not Playing"))
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.white)
            caption(playing?.artist ?? "")
            Button {
                environment.music.togglePlayPause()
            } label: {
                Label(playing?.isPlaying == true ? "Pause" : "Play", systemImage: playing?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, metrics.token(14))
                    .frame(minHeight: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                    .hubGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .opacity(density.showsControls ? 1 : 0)
            .allowsHitTesting(density.showsControls)
        }
        .lineLimit(1)
        .startsOnFirstUse { environment.music.start() }
    }

    private var homeWidget: some View {
        let snapshot = environment.home.snapshot
        let lightsOn = snapshot.accessories.filter { $0.kind == .light && $0.isOn }.count
        return VStack(alignment: .leading, spacing: metrics.token(2)) {
            Label(snapshot.homeName.isEmpty ? String(localized: "Home") : snapshot.homeName, systemImage: "house.fill")
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                .foregroundStyle(.white)
            if environment.home.access != .ready {
                caption(String(localized: "Not set up"))
            } else if let thermostat = snapshot.thermostats.first {
                hero(units.degrees(thermostat.currentCelsius))
                caption(String(localized: "Inside"))
                caption(String(localized: "\(lightsOn) lights on"))
            } else {
                hero("\(lightsOn)")
                caption(String(localized: "\(lightsOn) lights on"))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .startsOnFirstUse { environment.home.start() }
    }

    private var timersWidget: some View {
        let strip = environment.timers.strip
        return VStack(alignment: .leading, spacing: metrics.token(2)) {
            Label("Timers", systemImage: "timer")
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                .foregroundStyle(Color(RainbowTint.orange))
            if let first = strip.entries.first {
                hero(first.countdown)
                caption(first.name.isEmpty ? String(localized: "Timer") : first.name)
            } else if let next = environment.alarms.nextAlarm(calendar: calendar) {
                hero(next.date.formatted(date: .omitted, time: .shortened))
                caption(String(localized: "Next Alarm"))
            } else {
                caption(String(localized: "No Timers"))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Album art, or a neutral tile with a note when there is none.
struct ArtworkView: View {
    let image: UIImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(RainbowTint.blue), Color(RainbowTint.purple)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.all, 24)
                        .frame(maxWidth: 120, maxHeight: 120)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
