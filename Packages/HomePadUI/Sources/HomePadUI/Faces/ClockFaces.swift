import HomePadCore
import HomePadUICore
import SwiftUI

/// A solid color dial with four oversized numerals and white hands.
struct AnalogFace: View {
    let date: Date
    let sweeps: Bool
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.calendar) private var calendar

    @Environment(\.hubIsNight) private var isNight

    private var options: FaceOptions { preferences.faces }

    private var dialColor: Color {
        if isNight { return Color.black }
        switch options.analogColor {
        case .green: return Color(red: 0.24, green: 0.62, blue: 0.38)
        case .black: return Color.black
        default: return options.analogColor.tint.map { Color($0) } ?? Color.black
        }
    }

    private var inkColor: Color {
        isNight || options.analogColor == .black ? Color(white: 0.85) : .black
    }

    var body: some View {
        let detailed = density.showsLabels
        let numerals = options.analogNumerals
        let topInset = metrics.topBar * 0.85
        ZStack {
            Canvas { context, size in
                // The hands turn on a circle. The numerals sit toward the edges of whatever
                // shape the screen is, so a wide screen is filled edge to edge.
                let (center, radius, stretch) = ClockDrawing.dial(in: size, topInset: topInset)
                let angles = ClockHandAngles(reading: ClockReading(date: date, calendar: calendar), sweeps: sweeps)
                if options.analogShowsTicks {
                    ClockDrawing.ticks(context, center: center, radius: radius * 0.97, hoursOnly: false, color: inkColor, width: radius * 0.012)
                }
                let large = numerals == .large
                for hour in numerals.hours {
                    let onCircle = ClockDrawing.point(center: .zero, radius: radius, degrees: ClockDial.numeralAngle(hour: hour), fraction: large ? 0.62 : 0.78)
                    let position = CGPoint(x: center.x + onCircle.x * stretch.width, y: center.y + onCircle.y * stretch.height)
                    let text = Text(verbatim: "\(hour)")
                        .font(.system(size: radius * (large ? 0.98 : 0.2), weight: large ? .light : .medium))
                        .foregroundStyle(inkColor)
                    context.draw(text, at: position)
                }
                ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.hour, length: 0.4, width: radius * 0.05, color: .white)
                ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.minute, length: 0.68, width: radius * 0.05, color: .white)
                if detailed {
                    ClockDrawing.secondHand(context, center: center, radius: radius, degrees: angles.second, length: 0.9, width: radius * 0.012, color: .white)
                }
            }
            if detailed {
                Text(date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: metrics.text(3.2), weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(inkColor)
                    .padding(metrics.pt(5.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dialColor)
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
    }
}

/// A single-color dial whose embossed numerals are strongest near the minute hand and fade away
/// around the rest of the dial.
struct FadeFace: View {
    let date: Date
    let sweeps: Bool
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.hubIsNight) private var isNight

    private var palette: (dial: Color, hands: Color, second: Color) {
        if isNight { return (.black, Color(white: 0.85), .white) }
        switch preferences.faces.fadeColor {
        case .gray: return (Color(red: 0.6, green: 0.61, blue: 0.63), Color(white: 0.17), Color(red: 0.16, green: 0.45, blue: 0.95))
        case .rose: return (Color(red: 0.85, green: 0.7, blue: 0.69), Color(red: 0.36, green: 0.16, blue: 0.19), Color(red: 0.93, green: 0.55, blue: 0.72))
        }
    }

    var body: some View {
        let colors = palette
        let topInset = metrics.topBar * 0.85
        Canvas { context, size in
            let (center, radius, stretch) = ClockDrawing.dial(in: size, topInset: topInset)
            let angles = ClockHandAngles(reading: ClockReading(date: date, calendar: calendar), sweeps: sweeps)
            let spread: Double = density.showsLabels ? 115 : 75
            for hour in 1...12 {
                let opacity = ClockDial.fadeOpacity(numeralHour: hour, minuteAngle: angles.minute, spread: spread)
                guard opacity > 0.01 else { continue }
                let degrees = ClockDial.numeralAngle(hour: hour)
                let onCircle = ClockDrawing.point(center: .zero, radius: radius, degrees: degrees, fraction: 0.74)
                let position = CGPoint(x: center.x + onCircle.x * stretch.width, y: center.y + onCircle.y * stretch.height)
                let font = Font.system(size: radius * 0.24, weight: .medium, design: .rounded)
                var rotated = context
                rotated.translateBy(x: position.x, y: position.y)
                rotated.rotate(by: .degrees(degrees))
                // A dark copy below and a light copy on top read as numerals pressed into the dial.
                let offset = radius * 0.008
                rotated.draw(Text(verbatim: "\(hour)").font(font).foregroundStyle(.black.opacity(0.22 * opacity)), at: CGPoint(x: offset, y: offset))
                rotated.draw(Text(verbatim: "\(hour)").font(font).foregroundStyle(.white.opacity(0.5 * opacity)), at: .zero)
            }
            ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.hour, length: 0.44, width: radius * 0.04, color: colors.hands)
            ClockDrawing.hand(context, center: center, radius: radius, degrees: angles.minute, length: 0.72, width: radius * 0.04, color: colors.hands)
            ClockDrawing.secondHand(context, center: center, radius: radius, degrees: angles.second, length: 0.86, width: radius * 0.014, color: colors.second)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.dial)
        .accessibilityElement()
        .accessibilityLabel(Text(date, style: .time))
    }
}

/// A large digital time on black with two small widget spots underneath.
struct DigitalFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session

    var body: some View {
        let detailed = density.showsLabels
        let options = preferences.faces
        let tint = options.digitalAccent.tint(profileTint: session.activeProfile?.tint)
        let color = tint.map { Color($0) } ?? Color.white
        let time = FaceText.clock(date, calendar: calendar, density: density, units: units)
        VStack(spacing: metrics.pt(1)) {
            Text(FaceText.dateLine(date, calendar: calendar, density: density, locale: locale))
                .font(.system(size: metrics.text(detailed ? 3.6 : 5.4), weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.hubSecondaryText)
                .padding(.top, max(metrics.pt(detailed ? 9 : 16), metrics.topBar + metrics.pt(1)))
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: metrics.pt(1.5)) {
                Text(time.digits)
                    .font(.clockDigits(size: metrics.pt(detailed ? 31 : 39), style: options.digitalFont))
                    .contentTransition(.numericText())
                if let period = time.periodText {
                    Text(period)
                        .font(.clockDigits(size: metrics.pt(7), style: options.digitalFont))
                }
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, metrics.pt(5))
            Spacer(minLength: 0)
            if detailed {
                HStack {
                    weatherSpot
                    Spacer()
                    statusSpot
                }
                .padding(.horizontal, metrics.pt(8))
                .padding(.bottom, metrics.pt(8))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .combine)
        .startsOnFirstUse(when: detailed) { environment.weather.begin() }
    }

    private var weatherSpot: some View {
        let weather = environment.weather.snapshot
        return HStack(spacing: metrics.pt(1.6)) {
            Image(systemName: weather?.symbolName ?? "cloud.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: metrics.text(5)))
            VStack(alignment: .leading, spacing: 0) {
                Text(weather.map { units.degrees($0.temperatureCelsius) } ?? String(localized: "Weather"))
                    .font(.system(size: metrics.text(weather == nil ? 3.4 : 5), weight: .semibold))
                    .foregroundStyle(.white)
                Text(weather?.conditionText ?? WeatherMessage(problem: environment.weather.problem).title)
                    .font(.system(size: metrics.text(2.6)))
                    .foregroundStyle(Color.hubSecondaryText)
            }
        }
    }

    @ViewBuilder
    private var statusSpot: some View {
        if let playing = environment.music.nowPlaying, playing.isPlaying {
            miniStatus(symbol: "music.note", title: playing.title, subtitle: playing.artist)
        } else if let next = environment.alarms.nextAlarm(calendar: calendar) {
            miniStatus(symbol: "alarm.fill", title: next.date.formatted(date: .omitted, time: .shortened), subtitle: String(localized: "Next Alarm"))
        } else {
            miniStatus(symbol: "house.fill", title: environment.home.snapshot.homeName, subtitle: String(localized: "Home"))
        }
    }

    private func miniStatus(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: metrics.pt(1.6)) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(title)
                    .font(.system(size: metrics.text(3.4), weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: metrics.text(2.6)))
                    .foregroundStyle(Color.hubSecondaryText)
            }
            Image(systemName: symbol)
                .font(.system(size: metrics.text(5)))
                .foregroundStyle(.white)
        }
        .lineLimit(1)
        .frame(maxWidth: metrics.pt(40), alignment: .trailing)
    }
}

/// Six stripes in classic rainbow order with the time on top.
struct RainbowFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.hubIsNight) private var isNight

    var body: some View {
        let detailed = density.showsLabels
        let time = FaceText.clock(date, calendar: calendar, density: density, units: units)
        ZStack {
            VStack(spacing: 0) {
                ForEach(RainbowTint.allCases, id: \.self) { tint in
                    isNight ? Color.black : Color(tint)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: metrics.pt(1)) {
                Text(time.digits)
                    .font(.clockDigits(size: metrics.pt(detailed ? 30 : 38), weight: .bold))
                    .contentTransition(.numericText())
                if detailed {
                    Text(FaceText.dateLine(date, calendar: calendar, density: density, locale: locale))
                        .font(.system(size: metrics.text(4), weight: .semibold))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: metrics.pt(1), y: metrics.pt(0.4))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, metrics.pt(5))
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
