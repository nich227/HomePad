import HomePadCore
import HomePadUICore
import SwiftUI

/// A sky with the temperature in very large type, the time in the corner, and a row of details.
struct WeatherFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment

    private var detailed: Bool { density == .detailed }

    var body: some View {
        let weather = environment.weather.snapshot
        ZStack {
            WeatherSky()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: metrics.pt(0.4)) {
                        Label(weather?.conditionText ?? String(localized: "Weather Is Not Set Up"), systemImage: weather?.symbolName ?? "cloud.fill")
                        if let weather, detailed {
                            Text("H:\(units.degrees(weather.highCelsius)) L:\(units.degrees(weather.lowCelsius))")
                        }
                    }
                    Spacer()
                    Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                        .monospacedDigit()
                }
                .font(.system(size: metrics.text(detailed ? 3.4 : 4.6), weight: .semibold))
                .foregroundStyle(.white)
                if let weather {
                    Text(units.degrees(weather.temperatureCelsius))
                        .font(.system(size: metrics.pt(detailed ? 34 : 46), weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.top, metrics.pt(2))
                } else {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: metrics.pt(detailed ? 30 : 40)))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, metrics.pt(6))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                if detailed, weather != nil {
                    HStack(alignment: .top) {
                        stat("sunset.fill", weather?.sunset.map { $0.formatted(date: .omitted, time: .shortened) }, "Sunset")
                        stat("wind", weather?.windKilometersPerHour.map { windText($0) }, "Wind")
                        stat("humidity.fill", weather?.humidity.map { "\(Int(($0 * 100).rounded()))%" }, "Humidity")
                        stat("thermometer.high", weather.map { units.degrees($0.highCelsius) }, "High")
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(metrics.pt(7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func windText(_ kilometersPerHour: Double) -> String {
        let speed = Measurement(value: kilometersPerHour, unit: UnitSpeed.kilometersPerHour)
        return speed.formatted(.measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private func stat(_ symbol: String, _ value: String?, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: metrics.pt(0.8)) {
            Image(systemName: symbol)
                .font(.system(size: metrics.text(3.6)))
                .frame(height: metrics.pt(5))
            Text(value ?? "--").font(.system(size: metrics.text(2.7), weight: .semibold))
            Text(title).font(.system(size: metrics.text(2.5)))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

}

/// A daytime sky with soft cloud shapes, drawn rather than photographed.
struct WeatherSky: View {
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.62, green: 0.76, blue: 0.9), Color(red: 0.33, green: 0.56, blue: 0.86), Color(red: 0.2, green: 0.45, blue: 0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            ForEach(0..<4, id: \.self) { index in
                Ellipse()
                    .fill(.white.opacity(0.55))
                    .frame(width: metrics.pt(CGFloat(46 + index * 9)), height: metrics.pt(CGFloat(14 + index * 2)))
                    .blur(radius: metrics.pt(5))
                    .offset(x: metrics.pt(CGFloat(index * 22 - 30)), y: metrics.pt(CGFloat(-34 + index * 9)))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The month on a light card with today circled and the day number large behind the grid.
struct CalendarFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar

    private let ink = Color(red: 0.05, green: 0.14, blue: 0.36)
    private let dayBlue = Color(red: 0.1, green: 0.38, blue: 0.9)
    private let red = Color(RainbowTint.red)

    var body: some View {
        let grid = CalendarGrid(containing: date, calendar: calendar)
        let detailed = density == .detailed
        ZStack {
            Color(red: 0.94, green: 0.94, blue: 0.95)
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
                    monthGrid(grid)
                        .transition(.opacity)
                } else {
                    Spacer()
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.system(size: metrics.text(6), weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
            .padding(metrics.pt(7))
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
                            .foregroundStyle(day.isToday ? Color.white : (day.isInMonth ? dayBlue : Color(white: 0.72)))
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
