import HomePadCore
import HomePadUICore
import SwiftUI

/// A sky that follows the conditions, the temperature in very large type, the high and low, a
/// bar for the chance of rain, and a row of details for someone within reach.
struct WeatherFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let weather = environment.weather.snapshot
        ZStack {
            WeatherSky(kind: SkyKind(symbolName: weather?.symbolName))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: metrics.token(2)) {
                        Label(weather?.conditionText ?? WeatherMessage(problem: environment.weather.problem).title, systemImage: weather?.symbolName ?? "cloud.fill")
                            .symbolRenderingMode(.hierarchical)
                        if let weather {
                            Text(weather.locationName)
                                .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                                .opacity(density.showsLabels ? DesignTokens.subtitleOpacity : 0)
                        }
                    }
                    Spacer()
                    Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: metrics.textToken(density.showsLabels ? 19 : 26), weight: .semibold))
                .foregroundStyle(.white)
                if let weather {
                    Text(units.degrees(weather.temperatureCelsius))
                        .font(.system(size: metrics.token(DesignTokens.hero(for: density) * 2.4), weight: .light))
                        .foregroundStyle(.white.opacity(0.86))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text("H:\(units.degrees(weather.highCelsius))  L:\(units.degrees(weather.lowCelsius))")
                        .font(.system(size: metrics.textToken(24), weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    unavailable
                }
                Spacer(minLength: 0)
                if let weather, density.showsLabels {
                    precipitation(weather)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let weather, density.showsControls {
                    HStack(alignment: .top) {
                        stat("sunset.fill", weather.sunset.map { $0.formatted(date: .omitted, time: .shortened) }, "Sunset")
                        stat("wind", weather.windKilometersPerHour.map { windText($0) }, "Wind")
                        stat("humidity.fill", weather.humidity.map { "\(Int(($0 * 100).rounded()))%" }, "Humidity")
                        stat("thermometer.high", units.degrees(weather.highCelsius), "High")
                    }
                    .padding(.top, metrics.token(16))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, metrics.token(36))
            .padding(.top, metrics.topBar + metrics.token(4))
            .padding(.bottom, metrics.bottomBar + metrics.token(16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .startsOnFirstUse { environment.weather.begin() }
    }

    /// Why there is no weather, with the way into Settings when that is where the fix is.
    private var unavailable: some View {
        let message = WeatherMessage(problem: environment.weather.problem)
        return VStack(alignment: .leading, spacing: metrics.token(10)) {
            Image(systemName: message.symbol)
                .font(.system(size: metrics.token(density.showsLabels ? 110 : 150)))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, metrics.token(20))
                .accessibilityHidden(true)
            Text(message.detail)
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .opacity(density.showsLabels ? 1 : 0)
            if message.offersSettings, density.showsControls {
                HubSettingsButton()
            }
        }
        .accessibilityIdentifier("weather.unavailable")
    }

    /// The chance of rain or snow today as a bar that fills from the leading edge.
    private func precipitation(_ weather: WeatherSnapshot) -> some View {
        let chance = weather.precipitationChance ?? 0
        return VStack(alignment: .leading, spacing: metrics.token(6)) {
            HStack {
                Label("Precipitation", systemImage: "drop.fill")
                Spacer()
                Text(weather.precipitationChance.map { "\(Int(($0 * 100).rounded()))%" } ?? "--")
                    .monospacedDigit()
            }
            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
            .foregroundStyle(.white)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: max(proxy.size.height, proxy.size.width * chance))
                        .opacity(chance > 0 ? 1 : 0)
                }
            }
            .frame(height: metrics.token(8))
        }
        .padding(metrics.token(14))
        .hubTile(metrics)
        .accessibilityElement(children: .combine)
    }

    private func windText(_ kilometersPerHour: Double) -> String {
        let speed = Measurement(value: kilometersPerHour, unit: UnitSpeed.kilometersPerHour)
        return speed.formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func stat(_ symbol: String, _ value: String?, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: metrics.token(4)) {
            Image(systemName: symbol)
                .font(.system(size: metrics.textToken(20)))
                .frame(height: metrics.token(26))
            Text(value ?? "--").font(.system(size: metrics.textToken(15), weight: .semibold))
            Text(title).font(.system(size: metrics.textToken(13)))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// A sky drawn in code that follows the conditions: clear, cloud, rain, snow, storm, fog, or
/// night. Rain and snow fall unless motion is reduced. In Night Mode it is black.
struct WeatherSky: View {
    var kind: SkyKind = .clear
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubIsNight) private var isNight
    @Environment(\.hubMotion) private var motion

    private var colors: [Color] {
        switch kind {
        case .clear: [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.2, green: 0.47, blue: 0.88), Color(red: 0.13, green: 0.36, blue: 0.78)]
        case .cloudy: [Color(red: 0.62, green: 0.76, blue: 0.9), Color(red: 0.33, green: 0.56, blue: 0.86), Color(red: 0.2, green: 0.45, blue: 0.82)]
        case .rain, .storm: [Color(red: 0.3, green: 0.36, blue: 0.46), Color(red: 0.2, green: 0.26, blue: 0.38), Color(red: 0.12, green: 0.17, blue: 0.28)]
        case .snow, .fog: [Color(red: 0.7, green: 0.76, blue: 0.84), Color(red: 0.55, green: 0.63, blue: 0.75), Color(red: 0.42, green: 0.5, blue: 0.64)]
        case .night: [Color(red: 0.05, green: 0.08, blue: 0.24), Color(red: 0.08, green: 0.1, blue: 0.3), Color(red: 0.14, green: 0.12, blue: 0.36)]
        }
    }

    var body: some View {
        if isNight {
            Color.black.accessibilityHidden(true)
        } else {
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                if kind == .clear {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.9), Color(red: 1, green: 0.9, blue: 0.6).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: metrics.pt(30)))
                        .frame(width: metrics.pt(60), height: metrics.pt(60))
                        .position(x: metrics.width * 0.8, y: metrics.height * 0.22)
                }
                if kind == .night {
                    stars
                }
                if kind != .clear && kind != .night {
                    clouds(opacity: kind == .cloudy ? 0.55 : 0.32)
                }
                if kind.hasPrecipitation, !motion.reducesMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        precipitation(time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else if kind.hasPrecipitation {
                    precipitation(time: 0)
                }
            }
            .clipped()
            .accessibilityHidden(true)
        }
    }

    private func clouds(opacity: Double) -> some View {
        ForEach(0..<5, id: \.self) { index in
            Ellipse()
                .fill(.white.opacity(opacity))
                .frame(width: metrics.width * CGFloat(0.45 + Double(index) * 0.08), height: metrics.pt(CGFloat(14 + index * 2)))
                .blur(radius: metrics.pt(5))
                .position(x: metrics.width * CGFloat(0.12 + Double(index) * 0.2), y: metrics.height * CGFloat(0.12 + Double(index % 3) * 0.1))
        }
    }

    private var stars: some View {
        Canvas { context, size in
            for index in 0..<70 {
                let x = CGFloat((index * 73) % 101) / 101 * size.width
                let y = CGFloat((index * 37) % 89) / 89 * size.height * 0.7
                let radius = CGFloat(1 + index % 3) * 0.8
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(.white.opacity(0.35 + Double(index % 4) * 0.15)))
            }
        }
    }

    /// Streaks for rain, dots for snow, at fixed places that move down with time.
    private func precipitation(time: TimeInterval) -> some View {
        let isSnow = kind == .snow
        return Canvas { context, size in
            let speed: CGFloat = isSnow ? 0.12 : 0.9
            for index in 0..<90 {
                let x = CGFloat((index * 61) % 97) / 97 * size.width
                let phase = CGFloat((index * 29) % 83) / 83
                let y = ((phase + CGFloat(time) * speed * CGFloat(0.7 + Double(index % 5) * 0.12)).truncatingRemainder(dividingBy: 1)) * size.height
                if isSnow {
                    let radius = CGFloat(2 + index % 3)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(.white.opacity(0.8)))
                } else {
                    var streak = Path()
                    streak.move(to: CGPoint(x: x, y: y))
                    streak.addLine(to: CGPoint(x: x - size.height * 0.008, y: y + size.height * 0.035))
                    context.stroke(streak, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
                }
            }
        }
    }
}

/// The month on a light card with today circled and the day number large behind the grid.
struct CalendarFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar

    @Environment(\.hubIsNight) private var isNight

    private var ink: Color { isNight ? .white : Color(red: 0.05, green: 0.14, blue: 0.36) }
    private var dayBlue: Color { isNight ? .white : Color(red: 0.1, green: 0.38, blue: 0.9) }
    private var red: Color { isNight ? .white : Color(RainbowTint.red) }
    private var paper: Color { isNight ? .black : Color(red: 0.94, green: 0.94, blue: 0.95) }

    var body: some View {
        let grid = CalendarGrid(containing: date, calendar: calendar)
        let detailed = density.showsLabels
        // Where the screen is not square the large date keeps a part of its own: beside the
        // month on a wide screen, above it on a tall one.
        let isTall = metrics.height > metrics.width * 1.15
        let showsDate = detailed && (metrics.isLandscape || isTall)
        let layout = isTall ? AnyLayout(VStackLayout(spacing: metrics.token(12))) : AnyLayout(HStackLayout(spacing: metrics.token(24)))
        ZStack {
            paper
            // The large date belongs to the far layout. Up close the month grid stands alone and
            // marks today with a circle, so nothing is drawn through the numbers.
            if !detailed {
                Text(date, format: .dateTime.day())
                    .font(.system(size: metrics.pt(74), weight: .semibold).width(.condensed))
                    .foregroundStyle(red)
                    .offset(y: metrics.pt(6))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            VStack(spacing: metrics.pt(detailed ? 2.4 : 0)) {
                HStack {
                    Text(date, format: .dateTime.month(.wide).year())
                    Spacer()
                    Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                        .monospacedDigit()
                }
                .font(.system(size: metrics.text(detailed ? 4.2 : 6), weight: .semibold))
                .foregroundStyle(red)
                if detailed {
                    layout {
                        if showsDate {
                            VStack(spacing: 0) {
                                Text(date, format: .dateTime.day())
                                    .font(.system(size: metrics.pt(isTall ? 34 : 46), weight: .semibold).width(.condensed))
                                    .foregroundStyle(red)
                                    .contentTransition(.numericText())
                                Text(date, format: .dateTime.weekday(.wide))
                                    .font(.system(size: metrics.text(5), weight: .semibold))
                                    .foregroundStyle(ink)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityHidden(true)
                        }
                        monthGrid(grid)
                    }
                    .transition(.opacity)
                } else {
                    Spacer()
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.system(size: metrics.text(6), weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
            .padding(.horizontal, metrics.pt(7))
            .padding(.top, metrics.topBar + metrics.pt(1))
            .padding(.bottom, metrics.bottomBar + metrics.pt(3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monthGrid(_ grid: CalendarGrid) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: metrics.pt(1.2)) {
            GridRow {
                ForEach(grid.weekdayOrder, id: \.self) { weekday in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.system(size: metrics.text(4), weight: .bold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(grid.weeks.indices, id: \.self) { week in
                GridRow {
                    ForEach(grid.weeks[week]) { day in
                        Text(verbatim: "\(day.number)")
                            .font(.system(size: metrics.text(4.6), weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(day.isToday ? paper : (day.isInMonth ? dayBlue : Color(white: isNight ? 0.4 : 0.72)))
                            .frame(width: metrics.pt(8.2), height: metrics.pt(8.2))
                            .background(Circle().fill(day.isToday ? ink : Color.clear))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Text(day.date, format: .dateTime.month().day()))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
