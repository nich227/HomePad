import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadUICore
import SwiftUI

/// The small avatar in the corner of a face. A soft pulse shows that the hub sees someone.
struct ProfileChip: View {
    let profile: HouseholdProfile?
    let isSomeonePresent: Bool
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.pt(1.2)) {
                ZStack {
                    if isSomeonePresent {
                        HomePadAnimationView(.presencePulse, loop: true)
                            .frame(width: metrics.pt(8.5), height: metrics.pt(8.5))
                    }
                    ProfileAvatar(profile: profile, diameter: metrics.pt(5.6))
                }
                .frame(width: metrics.pt(8.5), height: metrics.pt(8.5))
                if profile == nil {
                    Text("Guest")
                        .font(.system(size: metrics.text(2.7), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.trailing, metrics.pt(2))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Capsule(), interactive: true)
        .hoverEffect(.highlight)
        .accessibilityLabel(profile.map { Text("Profile: \($0.name)") } ?? Text("Profile: Guest"))
        .accessibilityHint("Opens the profile switcher.")
    }
}

/// Picks who is using the hub by hand. This personalizes the hub but never unlocks personal
/// content; only a recognized face does that.
struct ProfileSwitcher: View {
    let session: HouseholdSession
    let showsSetupHint: Bool
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: metrics.pt(3.5)) {
                Text("Who Is Using HomePad?")
                    .font(.system(size: metrics.text(4.4), weight: .bold))
                    .foregroundStyle(.white)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: metrics.pt(4)) {
                        ForEach(session.profiles) { profile in
                            person(profile: profile, name: profile.name, isCurrent: session.activeProfile?.id == profile.id) {
                                try? session.switchManually(to: profile.id)
                                onClose()
                            }
                        }
                        person(profile: nil, name: String(localized: "Guest"), isCurrent: session.isGuest) {
                            session.lock()
                            onClose()
                        }
                    }
                    .padding(.horizontal, metrics.pt(2))
                }
                .scrollIndicators(.hidden)
                Text(showsSetupHint
                    ? "No one is set up yet. To add people, turn on Setup Mode in Settings."
                    : "Choosing a person here personalizes the hub. Personal content unlocks only when the hub recognizes their face.")
                    .font(.system(size: metrics.text(2.9)))
                    .foregroundStyle(Color.hubSecondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: metrics.pt(3)) {
                    OpenSettingsButton()
                        .buttonStyle(.glass)
                    Button("Done", action: onClose)
                        .buttonStyle(.glassProminent)
                }
                .font(.system(size: metrics.text(3.2), weight: .semibold))
            }
            .padding(metrics.pt(5))
            .frame(maxWidth: metrics.pt(84))
            .hubGlass(in: RoundedRectangle(cornerRadius: metrics.pt(7), style: .continuous))
            .accessibilityAddTraits(.isModal)
        }
    }

    private func person(profile: HouseholdProfile?, name: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: metrics.pt(1.4)) {
                ProfileAvatar(profile: profile, diameter: metrics.pt(15))
                    .overlay(Circle().stroke(.white, lineWidth: isCurrent ? metrics.pt(0.7) : 0))
                Text(name)
                    .font(.system(size: metrics.text(3.1), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: metrics.pt(19))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Running timers as one glass capsule at the bottom of a face.
struct TimerStripView: View {
    let strip: TimerStrip
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        if !strip.entries.isEmpty {
            Button(action: action) {
                TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
                    let live = environment.timers.strip
                    HStack(spacing: metrics.pt(3)) {
                        Image(systemName: "timer")
                            .foregroundStyle(Color(RainbowTint.orange))
                        ForEach(live.entries) { entry in
                            HStack(spacing: metrics.pt(1.2)) {
                                if !entry.name.isEmpty {
                                    Text(entry.name).foregroundStyle(.white.opacity(0.8))
                                }
                                Text(entry.countdown)
                                    .monospacedDigit()
                                    .foregroundStyle(entry.isFinished ? Color(RainbowTint.red) : (entry.isPaused ? Color.hubSecondaryText : .white))
                            }
                        }
                        if live.overflowCount > 0 {
                            Text(verbatim: "+\(live.overflowCount)").foregroundStyle(Color.hubSecondaryText)
                        }
                    }
                    .font(.system(size: metrics.text(3.3), weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, metrics.pt(4))
                    .frame(height: metrics.pt(8.5))
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hubGlass(in: Capsule(), interactive: true)
            .hoverEffect(.highlight)
            .padding(.bottom, metrics.pt(1))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("Timers")
            .accessibilityValue(Text(strip.entries.map { "\($0.name) \($0.countdown)" }.joined(separator: ", ")))
        }
    }
}

/// The nightstand clock: dim red digits on black. Red keeps eyes adjusted to the dark. Any tap
/// brings the normal hub back for a moment.
struct NightClockView: View {
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar

    var body: some View {
        TimelineView(.periodic(from: .startOfCurrentSecond, by: 5)) { timeline in
            let time = FaceText.clock(timeline.date, calendar: calendar, density: .glanceable, units: units)
            ZStack {
                Color.black
                Text(time.digits)
                    .font(.clockDigits(size: metrics.pt(34), weight: .medium))
                    .foregroundStyle(Color(red: 0.55, green: 0.04, blue: 0.02))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, metrics.pt(6))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Night clock")
        .accessibilityHint("Tap to wake the hub.")
    }
}

/// Covers the canvas when a timer finishes.
struct TimerDoneOverlay: View {
    let timers: [HubTimer]
    let onStop: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
            VStack(spacing: metrics.pt(3)) {
                HomePadAnimationView(.timerDone, loop: true)
                    .frame(width: metrics.pt(34), height: metrics.pt(34))
                Text(timers.count == 1 ? "Timer Done" : "Timers Done")
                    .font(.system(size: metrics.text(6.5), weight: .bold))
                    .foregroundStyle(.white)
                Text(timers.map { $0.name.isEmpty ? String(localized: "Timer") : $0.name }.joined(separator: ", "))
                    .font(.system(size: metrics.text(4), weight: .semibold))
                    .foregroundStyle(Color(RainbowTint.orange))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                GlassCapsuleButton(title: "Stop", symbol: "stop.fill", tint: Color(RainbowTint.orange).opacity(0.5), action: onStop)
                    .frame(width: metrics.pt(44))
                    .padding(.top, metrics.pt(3))
            }
            .padding(metrics.pt(8))
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// Covers the canvas while an alarm rings.
struct AlarmRingingOverlay: View {
    let alarm: HubAlarm
    let onSnooze: () -> Void
    let onStop: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
            VStack(spacing: metrics.pt(3)) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: metrics.pt(16)))
                    .foregroundStyle(Color(RainbowTint.orange))
                    .symbolEffect(.bounce, options: .repeating)
                Text(alarm.label.isEmpty ? String(localized: "Alarm") : alarm.label)
                    .font(.system(size: metrics.text(6.5), weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: metrics.pt(3)) {
                    GlassCapsuleButton(title: "Snooze", symbol: "zzz", action: onSnooze)
                    GlassCapsuleButton(title: "Stop", symbol: "stop.fill", tint: Color(RainbowTint.orange).opacity(0.5), action: onStop)
                }
                .padding(.top, metrics.pt(3))
            }
            .padding(metrics.pt(8))
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// First run: nobody is set up and setup mode is on.
struct HelloOverlay: View {
    let onAddPeople: () -> Void
    let onDismiss: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.86, blue: 0.72)
            Ellipse()
                .fill(RadialGradient(
                    colors: [Color(RainbowTint.red), Color(RainbowTint.orange), Color(RainbowTint.yellow).opacity(0)],
                    center: .center,
                    startRadius: metrics.pt(12),
                    endRadius: metrics.pt(46)
                ))
                .frame(width: metrics.pt(92), height: metrics.pt(74))
                .blur(radius: metrics.pt(4))
                .accessibilityHidden(true)
            VStack(spacing: metrics.pt(3)) {
                Spacer()
                HomePadAnimationView(.hello, loop: false)
                    .frame(width: metrics.pt(52), height: metrics.pt(30))
                Text("Welcome to HomePad")
                    .font(.system(size: metrics.text(4.6), weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: metrics.pt(3)) {
                    GlassCapsuleButton(title: "Not Now", symbol: "xmark", action: onDismiss)
                    GlassCapsuleButton(title: "Add People", symbol: "person.crop.circle.badge.plus", action: onAddPeople)
                }
            }
            .padding(metrics.pt(7))
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// An incoming page covering the whole screen, with a short arrival animation.
struct BeamTakeoverView: View {
    let content: @MainActor () -> AnyView
    let onClose: () -> Void
    @State private var showsArrival = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            content()
            if showsArrival {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    HomePadAnimationView(.beamIncoming, loop: false)
                        .frame(width: 260, height: 260)
                }
                .transition(.opacity)
                .accessibilityHidden(true)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hubGlass(in: Circle(), interactive: true)
            .hoverEffect(.highlight)
            .padding(24)
            .accessibilityLabel("Close")
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.35)) {
                showsArrival = false
            }
        }
    }
}

/// The second column of the fill layout: the same widgets as the Home Screen, stacked beside the
/// square canvas.
struct SideColumn: View {
    let isWide: Bool
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubAudience) private var audience

    private var kinds: [HubWidgetKind] {
        [.timers, .nowPlaying, .weather, .home].filter { VisibilityPolicy.visibility(of: $0, context: audience) == .visible }
    }

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: metrics.pt(2.4))) : AnyLayout(VStackLayout(spacing: metrics.pt(2.4)))
        layout {
            ForEach(kinds) { kind in
                WidgetContent(kind: kind)
                    .padding(metrics.pt(3.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .hubTile(metrics, tint: Color.white.opacity(0.06))
            }
        }
        .padding(.vertical, metrics.pt(3.2))
        .padding(.horizontal, metrics.pt(1.2))
    }
}
