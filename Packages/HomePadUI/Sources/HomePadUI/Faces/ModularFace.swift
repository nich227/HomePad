import HomePadCore
import HomePadUICore
import SwiftUI

/// Four widgets on black: the date, an analog clock, what is playing, and the weather. From
/// across the room only the date and the clock remain, at twice the size.
struct ModularFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session

    private var detailed: Bool { density == .detailed }

    private var accent: Color {
        session.activeProfile.map { Color($0.tint) } ?? Color(RainbowTint.orange)
    }

    var body: some View {
        VStack(spacing: metrics.pt(4)) {
            HStack(spacing: metrics.pt(4)) {
                dateTile
                AnalogDial(date: date, markers: .numerals, dialColor: Color(white: 0.13), secondColor: accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if detailed {
                HStack(alignment: .top, spacing: metrics.pt(4)) {
                    musicTile
                    weatherTile
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(metrics.pt(8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var dateTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.pt(1.4)) {
                Text(date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(accent)
                Text(date, format: .dateTime.month(.abbreviated)).foregroundStyle(.white)
            }
            .font(.system(size: metrics.pt(detailed ? 6.6 : 9), weight: .semibold))
            Text(date, format: .dateTime.day())
                .font(.system(size: metrics.pt(detailed ? 27 : 44), weight: .semibold).width(.condensed))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var musicTile: some View {
        let playing = environment.music.nowPlaying
        return VStack(alignment: .leading, spacing: metrics.pt(1.2)) {
            ArtworkView(image: environment.music.artwork, cornerRadius: metrics.pt(1.6))
                .frame(width: metrics.pt(15), height: metrics.pt(15))
            Text(playing?.title ?? String(localized: "Not Playing"))
                .font(.system(size: metrics.text(2.5), weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.white)
            Text(playing?.artist ?? "")
                .font(.system(size: metrics.text(2.4)))
                .foregroundStyle(Color.hubSecondaryText)
            Button {
                environment.music.togglePlayPause()
            } label: {
                Label(playing?.isPlaying == true ? "Pause" : "Play", systemImage: playing?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: metrics.text(2.4), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, metrics.pt(2.4))
                    .padding(.vertical, metrics.pt(1.1))
                    .background(Capsule().fill(Color(white: 0.22)))
            }
            .buttonStyle(.plain)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .startsOnFirstUse { environment.music.start() }
    }

    private var weatherTile: some View {
        let weather = environment.weather.snapshot
        return VStack(alignment: .leading, spacing: metrics.pt(0.6)) {
            HStack(spacing: metrics.pt(0.8)) {
                Text(weather?.locationName ?? String(localized: "Weather"))
                Image(systemName: "location.fill").font(.system(size: metrics.text(1.8)))
            }
            .font(.system(size: metrics.text(2.5), weight: .semibold))
            .foregroundStyle(.white)
            if let weather {
                Text(units.degrees(weather.temperatureCelsius))
                    .font(.system(size: metrics.pt(15), weight: .regular))
                    .foregroundStyle(.white)
            }
            Image(systemName: weather?.symbolName ?? "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: weather == nil ? metrics.pt(12) : metrics.text(3)))
            if weather == nil {
                Text("Not set up")
                    .font(.system(size: metrics.text(2.4), weight: .semibold))
                    .foregroundStyle(Color.hubSecondaryText)
            }
            if let weather {
                Text(weather.conditionText)
                    .font(.system(size: metrics.text(2.4), weight: .semibold))
                    .foregroundStyle(.white)
                Text("H:\(units.degrees(weather.highCelsius)) L:\(units.degrees(weather.lowCelsius))")
                    .font(.system(size: metrics.text(2.4), weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
