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
                        TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
                            VStack(spacing: metrics.pt(2)) {
                                ForEach(center.engine.timers) { timer in
                                    row(timer)
                                }
                            }
                        }
                        if center.lastError == .limitReached(center.engine.limit) {
                            Text("Remove a timer to add another.")
                                .font(.system(size: metrics.text(3)))
                                .foregroundStyle(Color(RainbowTint.red))
                        }
                        newTimer
                    }
                    .padding(.horizontal, metrics.pt(1))
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Presets as a three by three grid of tiles, each a large number over "MIN", the way the
    /// running timer captions its length.
    private var newTimer: some View {
        let gap = metrics.pt(2.2)
        let columns = metrics.columns(3)
        let cell = metrics.cell(count: columns, padding: metrics.pt(5), gap: gap)
        return VStack(alignment: .leading, spacing: metrics.pt(2.4)) {
            TextField("Name (optional)", text: $name)
                .font(.system(size: metrics.text(3.4)))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.pt(3.5))
                .frame(height: metrics.pt(9))
                .background(Capsule().fill(Color.hubTileFill))
                .accessibilityLabel("Timer name")
                .accessibilityIdentifier("timers.name")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: columns), spacing: gap) {
                ForEach(Self.presetMinutes, id: \.self) { minutes in
                    Button {
                        if let timer = environment.timers.add(name: name, duration: TimeInterval(minutes * 60)) {
                            focused = timer.id
                            name = ""
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(minutes)")
                                .font(.system(size: metrics.pt(11), weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text("MIN")
                                .font(.system(size: metrics.text(3), weight: .semibold))
                                .foregroundStyle(Color(RainbowTint.orange))
                        }
                        .frame(width: cell, height: cell * 0.62)
                        .background(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous).fill(Color.hubTileFill))
                        .contentShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Start a \(minutes) minute timer")
                    .accessibilityIdentifier("timers.preset.\(minutes)")
                }
            }
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
    private func controls(_ timer: HubTimer, size: CGFloat = 8) -> some View {
        let center = environment.timers
        switch timer.state {
        case .running:
            GlassCircleButton(symbol: "pause.fill", label: "Pause", size: size, identifier: "timers.pause") { center.pause(timer.id) }
        case .paused:
            GlassCircleButton(symbol: "play.fill", label: "Resume", size: size, identifier: "timers.resume") { center.resume(timer.id) }
        case .idle, .finished:
            GlassCircleButton(symbol: "play.fill", label: "Start", size: size, identifier: "timers.start") { center.start(timer.id) }
        }
        GlassCircleButton(symbol: "trash.fill", label: "Delete", size: size, identifier: "timers.delete") { center.remove(timer.id) }
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
                    // Sits above center so the controls have room inside the ring.
                    .padding(.bottom, metrics.pt(14))
                    .accessibilityElement(children: .combine)
                }
            }
            VStack {
                HStack {
                    GlassCircleButton(symbol: "chevron.left", label: "All Timers", identifier: "timers.all") { focused = nil }
                    Spacer()
                }
                Spacer()
                HStack(spacing: metrics.pt(5)) {
                    controls(timer, size: 12)
                }
                .padding(.bottom, metrics.pt(13))
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
    @State private var draft: AlarmTimeDraft?
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
                            .padding(.top, metrics.pt(5))
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

    /// The time being set. Starts at the next five minutes from now.
    private var currentDraft: AlarmTimeDraft {
        if let draft { return draft }
        let parts = calendar.dateComponents([.hour, .minute], from: Date())
        return AlarmTimeDraft(hour: parts.hour ?? 7, minute: parts.minute ?? 0)
    }

    private func step(_ change: (inout AlarmTimeDraft) -> Void) {
        var next = currentDraft
        change(&next)
        draft = next
    }

    /// The new alarm's time in large digits, with a pair of arrows for the hour and a pair for
    /// the minute, sized to press from across a counter.
    private var newAlarm: some View {
        let time = currentDraft
        let moment = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        return VStack(spacing: metrics.pt(2.4)) {
            HStack(spacing: metrics.pt(3)) {
                stepper(name: "hour", label: "Hour") { delta in step { $0.stepHour(by: delta) } }
                Text(moment, format: .dateTime.hour().minute())
                    .font(.system(size: metrics.pt(15), weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: time)
                    .accessibilityLabel("New alarm time")
                    .accessibilityIdentifier("alarms.time")
                stepper(name: "minute", label: "Minute") { delta in step { $0.stepMinute(by: delta) } }
            }
            HStack(spacing: metrics.pt(2)) {
                TextField("Label", text: $label)
                    .font(.system(size: metrics.text(3.4)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, metrics.pt(3.5))
                    .frame(height: metrics.pt(10))
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .accessibilityIdentifier("alarms.label")
                Button {
                    repeatsDaily.toggle()
                } label: {
                    Label("Daily", systemImage: "repeat")
                        .font(.system(size: metrics.text(3.2), weight: .semibold))
                        .foregroundStyle(repeatsDaily ? .black : .white)
                        .padding(.horizontal, metrics.pt(3.2))
                        .frame(height: metrics.pt(10))
                        .background(Capsule().fill(repeatsDaily ? Color(RainbowTint.orange) : Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Repeat every day")
                .accessibilityAddTraits(repeatsDaily ? .isSelected : [])
                .accessibilityIdentifier("alarms.repeat")
                GlassCapsuleButton(title: "Add", symbol: "plus", tint: Color(RainbowTint.orange).opacity(0.5), identifier: "alarms.add") {
                    environment.alarms.add(
                        hour: time.hour,
                        minute: time.minute,
                        label: label,
                        repeatDays: repeatsDaily ? Set(Weekday.allCases) : []
                    )
                    label = ""
                }
                .frame(width: metrics.pt(24), height: metrics.pt(10))
            }
        }
        .padding(metrics.pt(3))
        .background(RoundedRectangle(cornerRadius: metrics.pt(5), style: .continuous).fill(Color.hubTileFill))
    }

    private func stepper(name: String, label: LocalizedStringKey, change: @escaping (Int) -> Void) -> some View {
        VStack(spacing: metrics.pt(1.4)) {
            GlassCircleButton(symbol: "chevron.up", label: "Later", size: 10, identifier: "alarms.\(name).up") { change(1) }
            Text(label)
                .font(.system(size: metrics.text(2.6), weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.hubSecondaryText)
                .accessibilityHidden(true)
            GlassCircleButton(symbol: "chevron.down", label: "Earlier", size: 10, identifier: "alarms.\(name).down") { change(-1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
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
