import HomePadCore
import HomePadUICore
import SwiftUI

/// Tick marks around a rounded square that go dark clockwise as the timer runs down.
struct TimerRingView: View {
    let progress: Double
    var count = 60
    var lit: Color = Color(RainbowTint.orange)

    var body: some View {
        Canvas { context, size in
            let length = size.width * 0.045
            for tick in TimerRing.ticks(count: count, progress: progress) {
                let center = CGPoint(x: tick.x * size.width, y: tick.y * size.height)
                var rotated = context
                rotated.translateBy(x: center.x, y: center.y)
                // Ticks fan outward like a dial instead of standing square to the edge.
                let lean = atan2(tick.x - 0.5, 0.5 - tick.y) * 180 / .pi
                rotated.rotate(by: .degrees(lean))
                var path = Path()
                path.move(to: CGPoint(x: 0, y: -length / 2))
                path.addLine(to: CGPoint(x: 0, y: length / 2))
                rotated.stroke(path, with: .color(tick.isLit ? lit : lit.opacity(0.22)), style: StrokeStyle(lineWidth: size.width * 0.011, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct TimersApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment
    @State private var focused: UUID?
    @State private var name = ""

    private static let presetMinutes = [1, 3, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        let center = environment.timers
        if let id = focused, let timer = center.engine.timers.first(where: { $0.id == id }) {
            ringScreen(timer)
        } else {
            AppScreen(title: "Timers", onClose: onClose) {
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.pt(3)) {
                        newTimer
                        if center.lastError == .limitReached(center.engine.limit) {
                            Text("Remove a timer to add another.")
                                .font(.system(size: metrics.text(3)))
                                .foregroundStyle(Color(RainbowTint.red))
                        }
                        TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
                            VStack(spacing: metrics.pt(2)) {
                                ForEach(center.engine.timers) { timer in
                                    row(timer)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, metrics.pt(1))
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var newTimer: some View {
        VStack(alignment: .leading, spacing: metrics.pt(2)) {
            TextField("Name (optional)", text: $name)
                .font(.system(size: metrics.text(3.4)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.pt(3))
                .frame(height: metrics.pt(9))
                .background(Capsule().fill(Color.hubTileFill))
                .accessibilityLabel("Timer name")
            ScrollView(.horizontal) {
                HStack(spacing: metrics.pt(2)) {
                    ForEach(Self.presetMinutes, id: \.self) { minutes in
                        Button {
                            if let timer = environment.timers.add(name: name, duration: TimeInterval(minutes * 60)) {
                                focused = timer.id
                                name = ""
                            }
                        } label: {
                            Text("\(minutes) min")
                                .font(.system(size: metrics.text(3.3), weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, metrics.pt(3.4))
                                .frame(height: metrics.pt(9))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .hubGlass(in: Capsule(), tint: Color(RainbowTint.orange).opacity(0.35), interactive: true)
                        .accessibilityLabel("Start a \(minutes) minute timer")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ timer: HubTimer) -> some View {
        let engine = environment.timers.engine
        return HStack(spacing: metrics.pt(3)) {
            TimerRingView(progress: engine.progress(for: timer), count: 28)
                .frame(width: metrics.pt(11), height: metrics.pt(11))
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.name.isEmpty ? String(localized: "Timer") : timer.name)
                    .font(.system(size: metrics.text(3.2), weight: .semibold))
                    .foregroundStyle(Color.hubSecondaryText)
                Text(DurationText.countdown(engine.remaining(for: timer)))
                    .font(.clockDigits(size: metrics.pt(7), weight: .medium))
                    .foregroundStyle(timer.isFinished ? Color(RainbowTint.red) : .white)
            }
            .lineLimit(1)
            Spacer()
            controls(timer)
        }
        .padding(metrics.pt(2.6))
        .background(RoundedRectangle(cornerRadius: metrics.pt(5), style: .continuous).fill(Color.hubTileFill))
        .contentShape(Rectangle())
        .onTapGesture { focused = timer.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func controls(_ timer: HubTimer) -> some View {
        let center = environment.timers
        switch timer.state {
        case .running:
            GlassCircleButton(symbol: "pause.fill", label: "Pause", size: 8) { center.pause(timer.id) }
        case .paused:
            GlassCircleButton(symbol: "play.fill", label: "Resume", size: 8) { center.resume(timer.id) }
        case .idle, .finished:
            GlassCircleButton(symbol: "play.fill", label: "Start", size: 8) { center.start(timer.id) }
        }
        GlassCircleButton(symbol: "trash.fill", label: "Delete", size: 8) { center.remove(timer.id) }
    }

    /// One timer full screen: the ring of ticks, the time left, and the timer's length.
    private func ringScreen(_ timer: HubTimer) -> some View {
        let center = environment.timers
        return ZStack {
            Color.black
            TimelineView(.periodic(from: .startOfCurrentSecond, by: 0.5)) { _ in
                let engine = center.engine
                ZStack {
                    TimerRingView(progress: engine.progress(for: timer))
                    VStack(spacing: metrics.pt(0.5)) {
                        Text(DurationText.countdown(engine.remaining(for: timer)))
                            .font(.system(size: metrics.pt(20), weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                        Text(caption(timer))
                            .font(.system(size: metrics.text(4), weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color(RainbowTint.orange))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, metrics.pt(22))
                    .accessibilityElement(children: .combine)
                }
            }
            VStack {
                HStack {
                    GlassCircleButton(symbol: "chevron.left", label: "All Timers") { focused = nil }
                    Spacer()
                }
                Spacer()
                HStack {
                    controls(timer)
                }
                .padding(.bottom, metrics.pt(15))
            }
            .padding(metrics.pt(4))
        }
    }

    private func caption(_ timer: HubTimer) -> String {
        let parts = DurationText.compact(timer.duration)
        let length = parts.hours > 0
            ? String(localized: "\(parts.hours) hr \(parts.minutes) min")
            : String(localized: "\(parts.minutes) min")
        return timer.name.isEmpty ? length : "\(timer.name) \u{00B7} \(length)"
    }
}

struct AlarmsApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment
    @State private var time = Date()
    @State private var label = ""
    @State private var repeatsDaily = false

    var body: some View {
        let center = environment.alarms
        AppScreen(title: "Alarms", onClose: onClose) {
            ScrollView {
                VStack(spacing: metrics.pt(2)) {
                    newAlarm
                    if center.book.alarms.isEmpty {
                        Text("No Alarms")
                            .font(.system(size: metrics.text(4), weight: .semibold))
                            .foregroundStyle(Color.hubSecondaryText)
                            .padding(.top, metrics.pt(8))
                    }
                    ForEach(center.book.alarms) { alarm in
                        row(alarm)
                    }
                }
                .padding(.horizontal, metrics.pt(1))
            }
            .scrollIndicators(.hidden)
        }
    }

    private var newAlarm: some View {
        HStack(spacing: metrics.pt(2)) {
            DatePicker("Alarm time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
            TextField("Label", text: $label)
                .font(.system(size: metrics.text(3.2)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
            Button {
                repeatsDaily.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: metrics.pt(3.6), weight: .semibold))
                    .foregroundStyle(repeatsDaily ? Color(RainbowTint.orange) : Color.hubSecondaryText)
                    .frame(width: metrics.pt(8), height: metrics.pt(8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat every day")
            .accessibilityAddTraits(repeatsDaily ? .isSelected : [])
            GlassCircleButton(symbol: "plus", label: "Add Alarm", size: 8) {
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                environment.alarms.add(
                    hour: parts.hour ?? 7,
                    minute: parts.minute ?? 0,
                    label: label,
                    repeatDays: repeatsDaily ? Set(Weekday.allCases) : []
                )
                label = ""
            }
        }
        .padding(metrics.pt(2.6))
        .background(RoundedRectangle(cornerRadius: metrics.pt(5), style: .continuous).fill(Color.hubTileFill))
    }

    private func caption(_ alarm: HubAlarm) -> String {
        let title = alarm.label.isEmpty ? String(localized: "Alarm") : alarm.label
        return alarm.repeatDays.isEmpty ? title : String(localized: "\(title), every day")
    }

    private func row(_ alarm: HubAlarm) -> some View {
        let center = environment.alarms
        let moment = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
        return HStack(spacing: metrics.pt(3)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(moment, format: .dateTime.hour().minute())
                    .font(.system(size: metrics.pt(8), weight: .light))
                    .foregroundStyle(alarm.isEnabled ? .white : Color.hubSecondaryText)
                Text(caption(alarm))
            }
            .font(.system(size: metrics.text(3)))
            .foregroundStyle(Color.hubSecondaryText)
            .lineLimit(1)
            Spacer()
            Toggle("Alarm on", isOn: Binding(get: { alarm.isEnabled }, set: { center.setEnabled($0, id: alarm.id) }))
                .labelsHidden()
                .tint(Color(RainbowTint.green))
            GlassCircleButton(symbol: "trash.fill", label: "Delete", size: 8) { center.remove(alarm.id) }
        }
        .padding(metrics.pt(2.6))
        .background(RoundedRectangle(cornerRadius: metrics.pt(5), style: .continuous).fill(Color.hubTileFill))
        .accessibilityElement(children: .contain)
    }
}
