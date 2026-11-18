import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadUICore
import SwiftUI

/// Who the hub thinks is in front of it, and the way between the face and the Home Screen,
/// drawn in the black beside the canvas so nothing sits on a face. Tapping the avatar opens the
/// manual switcher.
struct BezelStatusView: View {
    let profile: HouseholdProfile?
    let isSomeonePresent: Bool
    let isOnFaces: Bool
    /// False on the Home Screen, whose header already shows the avatar and the name.
    let showsAvatar: Bool
    let indicator: @MainActor () -> AnyView
    let onProfile: () -> Void
    let onToggleSurface: () -> Void
    let onUnlock: () -> Void
    /// How far to stay in from each edge, to keep clear of a camera or the edge of the display.
    var clearance = EdgeInsets()
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock

    /// A button's side: nine units of the canvas, and never too small to press.
    private var buttonSide: CGFloat {
        max(metrics.pt(9), HubMetrics.minimumTouchSide)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - clearance.leading - clearance.trailing
            let height = proxy.size.height - clearance.top - clearance.bottom
            Group {
                if height > width * 1.4 {
                    VStack(spacing: metrics.pt(1.6)) {
                        if showsAvatar {
                            avatar(size: buttonSide, name: .below)
                        }
                        FittedToWidth(width: max(0, width - metrics.pt(2))) { indicator() }
                        if showsDeviceUnlock {
                            unlockButton(size: max(metrics.pt(11), HubMetrics.minimumTouchSide), showsCaption: true)
                        }
                        Spacer(minLength: 0)
                        surfaceButton(size: buttonSide)
                    }
                    .padding(.vertical, metrics.pt(3.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    row(width: width, height: height)
                }
            }
            .padding(clearance)
        }
    }

    /// The strip above the canvas or above the second column. The second column is narrow, so
    /// the buttons share what there is and the name shows only when it has room.
    private func row(width: CGFloat, height: CGFloat) -> some View {
        let spacing = metrics.pt(1.6)
        let padding = metrics.pt(2)
        let available = max(0, width - padding * 2)
        let buttons: CGFloat = showsDeviceUnlock ? 3 : 2
        let indicatorMinimum = metrics.pt(5)
        let nameWidth = metrics.pt(18)
        let size = max(0, min(buttonSide, height - metrics.pt(2), (available - spacing * buttons - indicatorMinimum) / buttons))
        let free = available - (size + spacing) * buttons
        let showsName = free - indicatorMinimum >= nameWidth
        let indicatorLimit = min(width * 0.4, free - (showsName ? nameWidth : 0))
        return HStack(spacing: spacing) {
            surfaceButton(size: size)
            Spacer(minLength: 0)
            if showsDeviceUnlock {
                unlockButton(size: size, showsCaption: false)
            }
            FittedToWidth(width: max(0, indicatorLimit)) { indicator() }
            if showsAvatar {
                avatar(size: size, name: showsName ? .beside : .hidden)
            }
        }
        .padding(.horizontal, padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum NamePlacement {
        case below, beside, hidden
    }

    private func avatar(size: CGFloat, name: NamePlacement) -> some View {
        let layout = name == .below ? AnyLayout(VStackLayout(spacing: metrics.pt(0.8))) : AnyLayout(HStackLayout(spacing: metrics.pt(1.2)))
        return Button(action: onProfile) {
            layout {
                if name == .beside {
                    nameText
                }
                ZStack {
                    if isSomeonePresent {
                        HomePadAnimationView(.presencePulse, loop: true)
                            .frame(width: size, height: size)
                    }
                    ProfileAvatar(profile: profile, diameter: size * 0.68)
                }
                .frame(width: size, height: size)
                if name == .below {
                    nameText
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(profile.map { Text("Profile: \($0.name)") } ?? Text("Profile: Guest"))
        .accessibilityHint("Opens the profile switcher.")
        .accessibilityIdentifier("hub.profile")
    }

    private var nameText: some View {
        Text(profile?.name ?? String(localized: "Guest"))
            .font(.system(size: metrics.text(2.4), weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }

    /// Large enough to press from a standing position.
    private func unlockButton(size: CGFloat, showsCaption: Bool) -> some View {
        Button(action: onUnlock) {
            VStack(spacing: metrics.pt(0.6)) {
                Image(systemName: "touchid")
                    .font(.system(size: size * 0.64))
                    .foregroundStyle(Color(RainbowTint.red))
                    .frame(width: size, height: size)
                    .hubGlass(in: Circle(), interactive: true)
                if showsCaption {
                    Text("Unlock")
                        .font(.system(size: metrics.text(2.4), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Unlock with Touch ID")
        .accessibilityIdentifier("hub.deviceUnlock")
    }

    private func surfaceButton(size: CGFloat) -> some View {
        Button(action: onToggleSurface) {
            Image(systemName: isOnFaces ? "square.grid.2x2.fill" : "clock.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Circle(), interactive: true)
        .hoverEffect(.highlight)
        .accessibilityLabel(isOnFaces ? "Show Home Screen" : "Show Face")
        .accessibilityIdentifier(isOnFaces ? "hub.showHomeScreen" : "hub.showFace")
    }
}

/// Shrinks a view from another package to fit the space beside the canvas. Its natural size is
/// measured first, because it is laid out for a full-width screen.
private struct FittedToWidth<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content
    @State private var natural: CGSize = .zero

    var body: some View {
        let scale = natural.width > width && natural.width > 0 ? width / natural.width : 1
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
            .scaleEffect(scale)
            .frame(width: natural.width * scale, height: natural.height * scale)
    }
}

/// Picks who is using the hub by hand. This personalizes the hub but never unlocks personal
/// content; only a recognized face does that.
struct ProfileSwitcher: View {
    let session: HouseholdSession
    let showsSetupHint: Bool
    let onUnlock: () -> Void
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock

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
                if showsDeviceUnlock {
                    GlassCapsuleButton(
                        title: "Unlock with Touch ID",
                        symbol: "touchid",
                        tint: Color(RainbowTint.red).opacity(0.45),
                        identifier: "switcher.deviceUnlock"
                    ) {
                        onUnlock()
                        onClose()
                    }
                }
                Text(showsSetupHint
                    ? "No one is set up yet. To add people, turn on Setup Mode in Settings."
                    : "Choosing a person here personalizes the hub. Personal content unlocks only when the hub recognizes their face.")
                    .font(.system(size: metrics.text(2.9)))
                    .foregroundStyle(Color.hubSecondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: metrics.pt(3)) {
                    HubSettingsButton()
                    GlassCapsuleButton(title: "Done", symbol: "checkmark", tint: Color.accentColor.opacity(0.6), identifier: "switcher.done", action: onClose)
                }
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
            .accessibilityIdentifier("hub.timerStrip")
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
        .accessibilityIdentifier("hub.nightClock")
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
                GlassCapsuleButton(title: "Stop", symbol: "stop.fill", tint: Color(RainbowTint.orange).opacity(0.5), identifier: "timers.stopRinging", action: onStop)
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

/// First run: nobody is set up and setup mode is on. A warm shape on cream behind the hello
/// animation, with the two choices underneath.
struct HelloOverlay: View {
    let onAddPeople: () -> Void
    let onDismiss: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.87, blue: 0.76)
            Ellipse()
                .fill(Color(RainbowTint.yellow))
                .frame(width: metrics.pt(88), height: metrics.pt(66))
                .blur(radius: metrics.pt(12))
                .opacity(0.75)
            Ellipse()
                .fill(Color(red: 1, green: 0.25, blue: 0.55))
                .frame(width: metrics.pt(46), height: metrics.pt(42))
                .offset(x: metrics.pt(-22), y: metrics.pt(2))
                .blur(radius: metrics.pt(9))
            Ellipse()
                .fill(Color(red: 1, green: 0.2, blue: 0.16))
                .frame(width: metrics.pt(66), height: metrics.pt(50))
                .offset(x: metrics.pt(5))
                .blur(radius: metrics.pt(7))
            VStack(spacing: metrics.pt(2)) {
                Spacer()
                HomePadAnimationView(authored: .hello)
                    .frame(width: metrics.pt(34), height: metrics.pt(34))
                Text("Welcome to HomePad")
                    .font(.system(size: metrics.text(5.4), weight: .bold))
                    .foregroundStyle(.white)
                Text("Add the people who live here so the hub can recognize them.")
                    .font(.system(size: metrics.text(3.2), weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, metrics.pt(10))
                Spacer()
                HStack(spacing: metrics.pt(2.4)) {
                    choice("Not Now", symbol: "xmark", identifier: "welcome.notNow", isPrimary: false, action: onDismiss)
                    choice("Add People", symbol: "person.crop.circle.badge.plus", identifier: "welcome.addPeople", isPrimary: true, action: onAddPeople)
                }
            }
            .padding(metrics.pt(5))
        }
        .clipped()
        .accessibilityAddTraits(.isModal)
    }
}

extension HelloOverlay {
    /// Solid capsules. Glass picks up the cream behind it and the white label is lost.
    private func choice(_ title: LocalizedStringKey, symbol: String, identifier: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        let ink = Color(red: 0.45, green: 0.09, blue: 0.1)
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: metrics.text(3.4), weight: .semibold))
                .foregroundStyle(isPrimary ? ink : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, metrics.pt(4))
                .frame(maxWidth: .infinity, minHeight: metrics.pt(11.5))
                .background(Capsule().fill(isPrimary ? Color.white : ink.opacity(0.55)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityIdentifier(identifier)
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

/// The Home Screen's widgets in the space beside the canvas: the second column of the fill
/// layout, or one side of a fold. They are drawn at their usual proportions and scaled to the
/// grid that fits the space best.
struct SideColumn: View {
    /// False where a timer strip is shown right above, so timers are not listed twice.
    var showsTimers = true
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubAudience) private var audience
    @Environment(HubEnvironment.self) private var environment

    /// The side of a widget on the Home Screen, in canvas units. Widgets are laid out for it.
    private static let designSide: CGFloat = 39.4

    private var kinds: [HubWidgetKind] {
        var kinds: [HubWidgetKind] = [.nowPlaying, .weather, .home, .clock]
        if showsTimers, !environment.timers.strip.entries.isEmpty {
            kinds.insert(.timers, at: 0)
        }
        return kinds.filter { VisibilityPolicy.visibility(of: $0, context: audience) == .visible }
    }

    var body: some View {
        GeometryReader { proxy in
            let gap = metrics.pt(2.4)
            let inset = metrics.pt(1.6)
            let design = max(metrics.pt(Self.designSide), 1)
            let grid = SidePanelGrid(
                width: Double(proxy.size.width - inset * 2),
                height: Double(proxy.size.height - inset * 2),
                gap: Double(gap),
                preferredSide: Double(design)
            )
            let tile = CGSize(width: grid.tileWidth, height: grid.tileHeight)
            let scale = min(tile.width, tile.height) / design
            let shown = Array(kinds.prefix(grid.count))
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<grid.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(shown.dropFirst(row * grid.columns).prefix(grid.columns)) { kind in
                            WidgetContent(kind: kind)
                                .padding(metrics.pt(3.4))
                                .frame(width: design, height: design, alignment: .topLeading)
                                .scaleEffect(scale)
                                .frame(width: tile.width, height: tile.height)
                                .hubTile(metrics, tint: Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(inset)
        }
        .clipped()
    }
}
