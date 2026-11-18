import HomePadCore
import HomePadUICore
import MediaPlayer
import SwiftUI

// MARK: Control center

/// The system volume slider. The only supported way for an app to show and change the device's
/// volume.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Glass modules over a heavy blur: brightness with the Night Mode switch, volume, Do Not
/// Disturb, accessibility, what is playing, timers, and who is using the hub. Opened by a swipe
/// down from the top trailing corner.
struct ControlCenterView: View {
    enum Module: Hashable {
        case brightness, volume, quiet, accessibility, intercom, assistant, nowPlaying, timers, profiles
    }

    let session: HouseholdSession
    let isNight: Bool
    let isQuiet: Bool
    let brightness: Double
    let showsIntercom: Bool
    let showsAssistant: Bool
    let showsSetupHint: Bool
    let onNight: () -> Void
    let onQuiet: () -> Void
    let onBrightness: (Double) -> Void
    let onOpen: (HubApp) -> Void
    let onAssistant: () -> Void
    let onUnlock: () -> Void
    let onClose: () -> Void

    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock
    @Environment(\.openURL) private var openURL
    @Environment(HubEnvironment.self) private var environment
    @State private var draggedBrightness: Double?

    private var modules: [(Module, TileGridPacker.Span)] {
        var modules: [(Module, TileGridPacker.Span)] = [
            (.brightness, .init(columns: 1, rows: 2)),
            (.volume, .init(columns: 1, rows: 2)),
            (.quiet, .single),
            (.accessibility, .single),
        ]
        if showsIntercom { modules.append((.intercom, .single)) }
        if showsAssistant { modules.append((.assistant, .single)) }
        modules.append((.nowPlaying, .init(columns: 2, rows: 1)))
        if !environment.timers.strip.entries.isEmpty {
            modules.append((.timers, .init(columns: 2, rows: 1)))
        }
        modules.append((.profiles, .init(columns: 2, rows: 1)))
        return modules
    }

    var body: some View {
        let columns = metrics.isLandscape ? 4 : 2
        let list = modules
        let packed = TileGridPacker.pack(list.map(\.1), in: TileGrid(columns: columns, rows: 9))
        let rows = packed.compactMap { $0.map { $0.row + $0.rowSpan } }.max() ?? 1
        let grid = TileGrid(columns: columns, rows: rows)
        let gaps = metrics.gutter * CGFloat(columns - 1)
        let cellWidth = min(metrics.token(150), (metrics.width - metrics.margin * 2 - gaps) / CGFloat(columns))
        let available = metrics.height - metrics.topBar - metrics.bottomBar
        let cell = min(metrics.token(112), (available - metrics.gutter * CGFloat(rows - 1)) / CGFloat(rows))
        let width = cellWidth * CGFloat(columns) + gaps
        ZStack {
            OverlayScrim(onDismiss: onClose)
            GlassEffectContainer(spacing: metrics.gutter) {
                TileBoard(grid: grid, gap: metrics.gutter) {
                    ForEach(Array(zip(list, packed)), id: \.0.0) { module, placement in
                        if let placement {
                            view(for: module.0)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .hubTile(metrics)
                                .tile(placement)
                        }
                    }
                }
            }
            .frame(width: width, height: cell * CGFloat(rows) + metrics.gutter * CGFloat(rows - 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private func view(for module: Module) -> some View {
        switch module {
        case .brightness: brightnessModule
        case .volume: volumeModule
        case .quiet:
            toggle("Do Not Disturb", symbol: isQuiet ? "moon.zzz.fill" : "moon.zzz", isOn: isQuiet, identifier: "control.quiet", action: onQuiet)
        case .accessibility:
            toggle("Accessibility", symbol: "accessibility", isOn: false, identifier: "control.accessibility") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        case .intercom:
            toggle("Intercom", symbol: "waveform", isOn: false, identifier: "control.intercom") { onOpen(.intercom) }
        case .assistant:
            toggle("Assistant", symbol: "sparkles", isOn: false, identifier: "control.assistant", action: onAssistant)
        case .nowPlaying: nowPlayingModule
        case .timers: timersModule
        case .profiles: profilesModule
        }
    }

    private func toggle(_ title: LocalizedStringKey, symbol: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                TileBadge(symbol: symbol, isOn: isOn)
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                    .foregroundStyle(isOn ? Color(white: 0.08) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(metrics.token(12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous).fill(.white)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// A tall track that fills from the bottom, with the Night Mode switch above it.
    private var brightnessModule: some View {
        let level = draggedBrightness ?? brightness
        return VStack(spacing: metrics.token(8)) {
            Button(action: onNight) {
                Image(systemName: isNight ? "moon.fill" : "moon")
                    .font(.system(size: metrics.token(20), weight: .semibold))
                    .foregroundStyle(isNight ? Color(white: 0.08) : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide), height: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                    .background(Circle().fill(isNight ? Color.white : Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Night Mode")
            .accessibilityAddTraits(isNight ? .isSelected : [])
            .accessibilityIdentifier("control.night")
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.18))
                    Rectangle().fill(.white).frame(height: proxy.size.height * level)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: metrics.token(18), weight: .semibold))
                        .foregroundStyle(level > 0.2 ? Color(white: 0.2) : .white)
                        .padding(.bottom, metrics.token(10))
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let next = Double(DimmerMath.brightness(forY: Double(value.location.y), height: Double(proxy.size.height))) / 100
                    draggedBrightness = next
                    onBrightness(next)
                })
            }
            .frame(width: metrics.token(64))
            .accessibilityElement()
            .accessibilityLabel("Brightness")
            .accessibilityValue(Text(verbatim: "\(Int((level * 100).rounded()))%"))
            .accessibilityAdjustableAction { direction in
                let next = min(max(level + (direction == .increment ? 0.1 : -0.1), 0), 1)
                draggedBrightness = next
                onBrightness(next)
            }
            .accessibilityIdentifier("control.brightness")
        }
        .padding(metrics.token(12))
    }

    /// The system's own slider, turned on its side to match the brightness track.
    private var volumeModule: some View {
        VStack(spacing: metrics.token(8)) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: metrics.token(20), weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                .accessibilityHidden(true)
            GeometryReader { proxy in
                SystemVolumeSlider()
                    .frame(width: proxy.size.height, height: HubMetrics.minimumTouchSide)
                    .rotationEffect(.degrees(-90))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .accessibilityLabel("Volume")
            .accessibilityIdentifier("control.volume")
        }
        .padding(metrics.token(12))
    }

    private var nowPlayingModule: some View {
        let playing = environment.music.nowPlaying
        return HStack(spacing: metrics.token(10)) {
            ArtworkView(image: environment.music.artwork, cornerRadius: metrics.token(10))
                .frame(width: metrics.token(48), height: metrics.token(48))
            VStack(alignment: .leading, spacing: 0) {
                Text(playing?.title ?? String(localized: "Not Playing"))
                    .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                    .foregroundStyle(.white)
                Text(playing?.artist ?? "")
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                    .foregroundStyle(Color.hubSecondaryText)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            transport(playing?.isPlaying == true ? "pause.fill" : "play.fill", label: "Play or Pause", identifier: "control.playPause", action: environment.music.togglePlayPause)
            transport("forward.fill", label: "Next", identifier: "control.next", action: environment.music.skipToNext)
        }
        .padding(.horizontal, metrics.token(14))
        .startsOnFirstUse { environment.music.start() }
    }

    private func transport(_ symbol: String, label: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        let side = max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var timersModule: some View {
        TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
            let strip = environment.timers.strip
            Button { onOpen(.timers) } label: {
                HStack(spacing: metrics.token(14)) {
                    Image(systemName: "timer")
                        .font(.system(size: metrics.token(26), weight: .semibold))
                        .foregroundStyle(Color(RainbowTint.orange))
                    ForEach(strip.entries.prefix(3)) { entry in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.countdown)
                                .font(.system(size: metrics.textToken(24), weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(entry.isFinished ? Color(RainbowTint.red) : .white)
                                .contentTransition(.numericText(countsDown: true))
                            Text(entry.name.isEmpty ? String(localized: "Timer") : entry.name)
                                .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                                .foregroundStyle(Color.hubSecondaryText)
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, metrics.token(14))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("control.timers")
        }
    }

    /// Guest and each member. Choosing one by hand personalizes the hub and never unlocks
    /// personal content; only a recognized face, or Touch ID after a camera match, does.
    private var profilesModule: some View {
        let side = max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide)
        return HStack(spacing: metrics.token(10)) {
            ForEach(session.profiles) { profile in
                person(profile: profile, name: profile.name, isCurrent: session.activeProfile?.id == profile.id, side: side) {
                    try? session.switchManually(to: profile.id)
                }
            }
            person(profile: nil, name: String(localized: "Guest"), isCurrent: session.isGuest, side: side) {
                session.lock()
            }
            Spacer(minLength: 0)
            if showsDeviceUnlock {
                GlassCircleButton(symbol: "touchid", label: "Unlock with Touch ID", size: 9, identifier: "switcher.deviceUnlock") {
                    onUnlock()
                    onClose()
                }
            }
            GlassCircleButton(symbol: "gearshape.fill", label: showsSetupHint ? "Open Settings to add people" : "Open Settings", size: 9, identifier: "control.settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        }
        .padding(.horizontal, metrics.token(14))
    }

    private func person(profile: HouseholdProfile?, name: String, isCurrent: Bool, side: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: metrics.token(2)) {
                ProfileAvatar(profile: profile, diameter: side)
                    .overlay(Circle().stroke(.white, lineWidth: isCurrent ? max(2, metrics.token(3)) : 0))
                Text(name)
                    .font(.system(size: metrics.textToken(12), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("switcher.\(profile?.name ?? "guest")")
    }
}

// MARK: Face picker

/// The faces as a row of live previews, one page each. A tap chooses one. Face options are not
/// here: the Customize button opens HomePad's page in the Settings app.
struct FacePickerView: View {
    let faces: [FaceKind]
    @Binding var selection: FaceKind?
    let facePosition: (@MainActor () -> FacePosition?)?
    let onChoose: (FaceKind) -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(\.openURL) private var openURL
    @State private var centered: FaceKind?

    private static let scale: CGFloat = 0.6

    var body: some View {
        let preview = CGSize(width: metrics.width * Self.scale, height: metrics.height * Self.scale)
        ZStack {
            Color.black
            VStack(spacing: metrics.token(14)) {
                Text((centered ?? selection)?.title ?? "")
                    .font(.system(size: metrics.textToken(22), weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .padding(.top, metrics.topBar)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: metrics.token(20)) {
                        ForEach(faces) { kind in
                            Button { onChoose(kind) } label: {
                                // The preview is a picture of the face: its own controls do
                                // not take touches, and the whole card is the button.
                                Color.clear
                                    .frame(width: preview.width, height: preview.height)
                                    .overlay {
                                        FaceView(kind: kind, facePosition: facePosition)
                                            .environment(\.hubMayPrompt, false)
                                            .frame(width: metrics.width, height: metrics.height)
                                            .scaleEffect(Self.scale)
                                            .allowsHitTesting(false)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: metrics.token(36), style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: metrics.token(36), style: .continuous)
                                            .stroke(.white.opacity(kind == selection ? 0.9 : 0.25), lineWidth: kind == selection ? 3 : 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: metrics.token(36), style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                    .opacity(phase.isIdentity ? 1 : 0.6)
                            }
                            .id(kind)
                            .accessibilityLabel(kind.title)
                            .accessibilityIdentifier("picker.face.\(kind.rawValue)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (metrics.width - preview.width) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
                .scrollIndicators(.hidden)
                .frame(height: preview.height)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                        .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, metrics.token(22))
                        .frame(height: max(metrics.token(DesignTokens.pillHeight), HubMetrics.minimumTouchSide))
                        .hubGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Settings, where face options are.")
                .accessibilityIdentifier("picker.customize")
                Spacer(minLength: metrics.bottomBar)
            }
        }
        .onAppear { centered = selection }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: Thermostat dial

private struct DialArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(ThermostatDial.startAngle - 90),
            endAngle: .degrees(ThermostatDial.endAngle - 90),
            clockwise: false
        )
        return path
    }
}

/// One thermostat as a dial: an arc from cool blue to warm amber, a thumb to drag, the target
/// in very large numerals, the temperature inside, and the mode.
struct ThermostatDialView: View {
    let thermostat: HomeThermostat
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(\.hubMotion) private var motion
    @Environment(HubEnvironment.self) private var environment
    @State private var dragged: Double?

    var body: some View {
        let target = dragged ?? thermostat.targetCelsius
        let side = min(metrics.token(340), metrics.height - metrics.topBar - metrics.bottomBar - metrics.token(110), metrics.width - metrics.margin * 2)
        let line = metrics.token(22)
        ZStack {
            OverlayScrim(onDismiss: onClose)
            VStack(spacing: metrics.token(18)) {
                RoomBadge(text: thermostat.roomName.isEmpty ? thermostat.name : thermostat.roomName)
                ZStack {
                    DialArc()
                        .stroke(
                            AngularGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.4, green: 0.8, blue: 0.9), Color.hubAmber, Color(red: 1, green: 0.45, blue: 0.2)],
                                center: .center,
                                startAngle: .degrees(ThermostatDial.startAngle - 90),
                                endAngle: .degrees(ThermostatDial.endAngle - 90)
                            ),
                            style: StrokeStyle(lineWidth: line, lineCap: .round)
                        )
                        .padding(line / 2)
                    thumb(for: target, side: side, line: line)
                    VStack(spacing: 0) {
                        Text(verbatim: "\(units.temperature.rounded(fromCelsius: target))")
                            .font(.system(size: side * 0.36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(motion.snappy, value: target)
                        Text("Inside \(units.degrees(thermostat.currentCelsius))")
                            .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                            .foregroundStyle(Color.hubSecondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(width: side, height: side)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let next = ThermostatDial.celsius(
                        forOffsetX: Double(value.location.x - side / 2),
                        y: Double(value.location.y - side / 2),
                        unit: units.temperature
                    )
                    guard next != dragged else { return }
                    dragged = next
                    Task { await environment.home.setTargetTemperature(celsius: next, thermostatID: thermostat.id) }
                })
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(thermostat.name))
                .accessibilityAdjustableAction { direction in
                    let next = ThermostatMath.stepped(targetCelsius: target, direction: direction == .increment ? 1 : -1, unit: units.temperature)
                    dragged = next
                    Task { await environment.home.setTargetTemperature(celsius: next, thermostatID: thermostat.id) }
                }
                .accessibilityIdentifier("thermostat.dial")
                if let mode = thermostat.mode {
                    modes(selected: mode)
                }
            }
            GlassCircleButton(symbol: "xmark", label: "Close", identifier: "overlay.close", action: onClose)
                .padding(.top, metrics.topBar)
                .padding(.leading, metrics.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func thumb(for celsius: Double, side: CGFloat, line: CGFloat) -> some View {
        let angle = ThermostatDial.angle(forCelsius: celsius) * .pi / 180
        let radius = side / 2 - line / 2
        return Circle()
            .fill(.white)
            .frame(width: line * 1.5, height: line * 1.5)
            .shadow(color: .black.opacity(0.35), radius: line * 0.3)
            .offset(x: radius * CGFloat(sin(angle)), y: -radius * CGFloat(cos(angle)))
            .animation(motion.snappy, value: celsius)
            .accessibilityHidden(true)
    }

    private func modes(selected: ThermostatMode) -> some View {
        GlassEffectContainer {
            HStack(spacing: metrics.token(6)) {
                ForEach(ThermostatMode.allCases, id: \.self) { mode in
                    let isSelected = mode == selected
                    Button {
                        Task { await environment.home.setThermostatMode(mode, thermostatID: thermostat.id) }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                            .foregroundStyle(isSelected ? Color(white: 0.08) : .white)
                            .padding(.horizontal, metrics.token(16))
                            .frame(height: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                            .background {
                                if isSelected {
                                    Capsule().fill(.white)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hubGlass(in: Capsule(), tint: isSelected ? .white : nil, interactive: true)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("thermostat.mode.\(mode.rawValue)")
                }
            }
            .animation(motion.snappy, value: selected)
        }
    }
}

extension ThermostatMode {
    var title: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .heat: "Heat"
        case .cool: "Cool"
        case .auto: "Auto"
        }
    }
}

// MARK: Dimmer

/// One light as a tall pill that fills from the bottom in warm amber. Under it, the whites the
/// light can show, when it reports that it can change them.
struct DimmerView: View {
    let accessory: HomeAccessory
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(HubEnvironment.self) private var environment
    @State private var dragged: Int?

    private static func color(forMireds mireds: Int) -> Color {
        switch mireds {
        case 400...: Color(red: 1, green: 0.72, blue: 0.42)
        case 330..<400: Color(red: 1, green: 0.82, blue: 0.6)
        case 250..<330: Color(red: 1, green: 0.9, blue: 0.78)
        case 190..<250: Color(red: 1, green: 0.96, blue: 0.92)
        default: Color(red: 0.86, green: 0.92, blue: 1)
        }
    }

    var body: some View {
        let level = dragged ?? (accessory.isOn ? accessory.brightness ?? 0 : 0)
        let height = min(metrics.token(320), metrics.height - metrics.topBar - metrics.bottomBar - metrics.token(150))
        let width = height * 120 / 320
        ZStack {
            OverlayScrim(onDismiss: onClose)
            VStack(spacing: metrics.token(16)) {
                VStack(spacing: metrics.token(2)) {
                    Text(accessory.name)
                        .font(.system(size: metrics.textToken(22), weight: .bold))
                        .foregroundStyle(.white)
                    Text(verbatim: "\(accessory.roomName) \u{00B7} \(level)%")
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                        .foregroundStyle(Color.hubSecondaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                ZStack(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.16))
                    Rectangle().fill(Color.hubAmber).frame(height: height * CGFloat(level) / 100)
                    Image(systemName: level > 0 ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: width * 0.26, weight: .semibold))
                        .foregroundStyle(level > 12 ? Color(white: 0.15) : .white)
                        .padding(.bottom, width * 0.16)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: height * 40 / 320, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let next = DimmerMath.brightness(forY: Double(value.location.y), height: Double(height))
                    guard next != dragged else { return }
                    dragged = next
                    Task { await environment.home.setBrightness(next, accessoryID: accessory.id) }
                })
                .animation(motion.snappy, value: level)
                .accessibilityElement()
                .accessibilityLabel("Brightness")
                .accessibilityValue(Text(verbatim: "\(level)%"))
                .accessibilityAdjustableAction { direction in
                    let next = min(max(level + (direction == .increment ? 10 : -10), 0), 100)
                    dragged = next
                    Task { await environment.home.setBrightness(next, accessoryID: accessory.id) }
                }
                .accessibilityIdentifier("dimmer.track")
                if let current = accessory.colorTemperature {
                    HStack(spacing: metrics.token(10)) {
                        ForEach(DimmerMath.temperatureSwatches, id: \.self) { mireds in
                            let nearest = DimmerMath.temperatureSwatches.min { abs($0 - current) < abs($1 - current) }
                            Button {
                                Task { await environment.home.setColorTemperature(mireds, accessoryID: accessory.id) }
                            } label: {
                                Circle()
                                    .fill(Self.color(forMireds: mireds))
                                    .frame(width: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide), height: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                                    .overlay(Circle().stroke(.white, lineWidth: nearest == mireds ? 3 : 0).padding(-4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color temperature")
                            .accessibilityAddTraits(nearest == mireds ? .isSelected : [])
                            .accessibilityIdentifier("dimmer.swatch.\(mireds)")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: Camera

/// One camera over the whole canvas, live, with its room in the corner. The microphone button
/// is there only for a camera that reports two-way audio.
struct CameraZoomView: View {
    let camera: HomeCamera
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment
    @State private var isTalking = false

    var body: some View {
        ZStack {
            Color.black
            environment.home.cameraView(id: camera.id, live: true)
            VStack {
                HStack {
                    RoomBadge(text: camera.roomName.isEmpty ? camera.name : camera.roomName)
                    Spacer()
                    GlassCircleButton(symbol: "xmark", label: "Close", identifier: "overlay.close", action: onClose)
                }
                Spacer()
                if camera.supportsTwoWayAudio {
                    Button {
                        isTalking.toggle()
                        let talking = isTalking
                        Task { await environment.home.setCameraTalk(talking, cameraID: camera.id) }
                    } label: {
                        Image(systemName: isTalking ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: metrics.token(24), weight: .semibold))
                            .foregroundStyle(isTalking ? Color(white: 0.08) : .white)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: max(metrics.token(64), HubMetrics.minimumTouchSide), height: max(metrics.token(64), HubMetrics.minimumTouchSide))
                            .background {
                                if isTalking {
                                    Circle().fill(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .hubGlass(in: Circle(), interactive: true)
                    .accessibilityLabel(isTalking ? "Stop Talking" : "Talk")
                    .accessibilityIdentifier("camera.talk")
                }
            }
            .padding(.horizontal, metrics.margin)
            .padding(.top, metrics.topBar)
            .padding(.bottom, metrics.bottomBar + metrics.token(12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onDisappear {
            if isTalking {
                Task { await environment.home.setCameraTalk(false, cameraID: camera.id) }
            }
        }
    }
}
