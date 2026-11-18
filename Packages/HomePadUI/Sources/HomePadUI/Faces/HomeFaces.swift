import HomePadCore
import HomePadUICore
import SwiftUI

private struct HubSendKey: EnvironmentKey {
    static let defaultValue: @MainActor (HubEvent) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Sends an event to the hub's state machine: open an app, an inline control, an overlay.
    var hubSend: @MainActor (HubEvent) -> Void {
        get { self[HubSendKey.self] }
        set { self[HubSendKey.self] = newValue }
    }
}

/// One tile of the home: a round badge with its glyph at the top and two lines of text at the
/// bottom. A tap switches it and a held press opens its slider. A tile that is on is solid white
/// with dark text.
struct HomeTileView: View {
    let tile: HomeTile
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubAudience) private var audience
    @Environment(\.hubMayRunScenes) private var mayRunScenes
    @Environment(\.hubMotion) private var motion
    @Environment(\.hubSend) private var send
    @Environment(HubEnvironment.self) private var environment

    private var isOn: Bool {
        if case .accessory(let accessory) = tile { return accessory.isOn && accessory.kind != .lock }
        return false
    }

    /// A scene someone unrecognized is looking at: shown, but it will not run.
    private var isLockedScene: Bool {
        if case .scene = tile { return !mayRunScenes }
        return false
    }

    private var content: (symbol: String, title: String, subtitle: String) {
        switch tile {
        case .accessory(let accessory):
            let symbol = accessory.kind == .lock ? (accessory.isOn ? "lock.fill" : "lock.open.fill") : accessory.kind.symbolName
            return (symbol, accessory.name, accessory.roomName)
        case .scene(let scene):
            return (scene.symbolName, scene.name, isLockedScene ? String(localized: "Members only") : String(localized: "Scene"))
        case .camera(let camera):
            return ("video.fill", camera.name, camera.roomName)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
        let info = content
        Group {
            if case .camera(let camera) = tile {
                cameraTile(camera)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        TileBadge(symbol: info.symbol, isOn: isOn)
                        Spacer(minLength: 0)
                        if isLockedScene {
                            Image(systemName: "lock.fill")
                                .font(.system(size: metrics.textToken(13), weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 0)
                    TileCaption(title: info.title, subtitle: info.subtitle, isOn: isOn)
                }
                .padding(metrics.token(14))
                .opacity(isLockedScene ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isOn {
                shape.fill(Color.white)
            }
        }
        .hubGlass(in: shape, tint: isOn ? Color.white : nil, interactive: true)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: activate)
        .onLongPressGesture(minimumDuration: 0.45, perform: openDetail)
        .animation(motion.snappy, value: isOn)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(info.title), \(info.subtitle)"))
        .accessibilityHint(isLockedScene ? Text("Scenes run only for household members the hub recognizes.") : Text(verbatim: ""))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open Controls", openDetail)
        .accessibilityIdentifier("home.tile.\(tile.id)")
    }

    private func cameraTile(_ camera: HomeCamera) -> some View {
        environment.home.cameraView(id: camera.id, live: false)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color(RainbowTint.red))
                    .frame(width: metrics.token(8), height: metrics.token(8))
                    .padding(metrics.token(12))
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                Text(camera.name)
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: metrics.token(3))
                    .padding(metrics.token(12))
                    .opacity(density.showsLabels ? 1 : 0)
            }
    }

    private func activate() {
        switch tile {
        case .accessory(let accessory):
            guard HomeControlPolicy.mayOperate(accessory, turningOn: !accessory.isOn, isGuest: audience.isGuest) else { return }
            Task { await environment.home.setPower(!accessory.isOn, accessoryID: accessory.id) }
        case .scene(let scene):
            guard mayRunScenes else { return }
            Task { await environment.home.runScene(id: scene.id) }
        case .camera(let camera):
            send(.tapInlineControl(.camera(id: camera.id)))
        }
    }

    /// The slider behind a tile, for an accessory that has one.
    private func openDetail() {
        if case .accessory(let accessory) = tile, accessory.brightness != nil {
            send(.tapInlineControl(.dimmer(id: accessory.id)))
        }
    }
}

/// The large thermostat tile: a badge, the target temperature in very large numerals, the name
/// and room, and a chevron on each side to step it. A tap anywhere else opens the dial.
struct ThermostatTile: View {
    let thermostat: HomeThermostat
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubSend) private var send
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
        VStack(spacing: 0) {
            TileBadge(symbol: "thermometer.medium", points: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(verbatim: "\(units.temperature.rounded(fromCelsius: thermostat.targetCelsius))")
                .font(.system(size: metrics.token(DesignTokens.hero(for: density) * 1.5), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 0) {
                step(-1, symbol: "chevron.down", label: "Lower Temperature")
                Spacer(minLength: 0)
                VStack(spacing: metrics.token(1)) {
                    Text(thermostat.name)
                        .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                        .foregroundStyle(.white)
                    Text(thermostat.roomName)
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                        .foregroundStyle(Color.hubSecondaryText)
                        .opacity(density.showsLabels ? 1 : 0)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                step(1, symbol: "chevron.up", label: "Raise Temperature")
            }
        }
        .padding(metrics.token(14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hubGlass(in: shape, interactive: true)
        .contentShape(shape)
        .onTapGesture { send(.tapInlineControl(.thermostat(id: thermostat.id))) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open Thermostat") { send(.tapInlineControl(.thermostat(id: thermostat.id))) }
        .accessibilityIdentifier("home.thermostat")
    }

    private func step(_ direction: Int, symbol: String, label: LocalizedStringKey) -> some View {
        let side = max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide)
        return Button {
            let target = ThermostatMath.stepped(targetCelsius: thermostat.targetCelsius, direction: direction, unit: units.temperature)
            Task { await environment.home.setTargetTemperature(celsius: target, thermostatID: thermostat.id) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: metrics.token(24), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(density.showsControls ? 1 : 0)
        .allowsHitTesting(density.showsControls)
        .accessibilityHidden(!density.showsControls)
        .accessibilityLabel(label)
        .accessibilityIdentifier(direction > 0 ? "home.thermostat.up" : "home.thermostat.down")
    }
}

/// The analog clock on a frosted disc, as a tile.
struct ClockTile: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(HouseholdSession.self) private var session

    var body: some View {
        let accent = session.activeProfile.map { Color($0.tint) } ?? Color(RainbowTint.orange)
        AnalogDial(date: date, markers: .minuteTicks, dialColor: Color.white.opacity(0.1), secondColor: accent)
            .padding(metrics.token(10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hubTile(metrics)
    }
}

/// The home as a bento of glass tiles over the wallpaper: a large thermostat, a clock, a camera,
/// and a dock of quick toggles, on the grid the space gives.
struct HomeModularFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let home = environment.home
        let board = metrics.boardSize
        let grid = TileGrid(width: Double(board.width), height: Double(board.height))
        let tiles = HomeFavorites.smallTiles(in: home.snapshot, limit: grid.cellCount)
        let placed = HomeModularLayout.placements(in: grid, tileCount: tiles.count)
        ZStack {
            HubWallpaper()
            GlassEffectContainer(spacing: metrics.gutter) {
                TileBoard(grid: grid, gap: metrics.gutter) {
                    ForEach(placed, id: \.slot) { item in
                        slotView(item.slot, tiles: tiles)
                            .tile(item.placement)
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                    }
                }
                .animation(motion.spring, value: placed.map(\.slot))
            }
            .frame(width: board.width, height: board.height)
            .padding(metrics.boardInsets)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .startsOnFirstUse { home.start() }
    }

    @ViewBuilder
    private func slotView(_ slot: HomeModularLayout.Slot, tiles: [HomeTile]) -> some View {
        switch slot {
        case .hero:
            if let thermostat = environment.home.snapshot.thermostats.first {
                ThermostatTile(thermostat: thermostat)
            } else {
                noHomeTile
            }
        case .clock:
            ClockTile(date: date)
        case .tile(let index):
            HomeTileView(tile: tiles[index])
        }
    }

    private var noHomeTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            TileBadge(symbol: "house.fill", points: 40)
            Spacer(minLength: 0)
            Text(homeMessage)
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle + 5), weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(metrics.token(14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hubTile(metrics)
    }

    private var homeMessage: String {
        switch environment.home.access {
        case .ready: environment.home.snapshot.homeName
        case .denied: String(localized: "Allow Home access in Settings")
        case .noHomes: String(localized: "No home is set up")
        case .unknown: String(localized: "Home")
        }
    }
}

/// One, four, or nine cameras edge to edge with a thin gutter. A tap opens one full screen.
struct HomeCameraFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.hubSend) private var send
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let home = environment.home
        let cameras = Array(home.snapshot.cameras.prefix(CameraGrid.limit))
        let dimensions = CameraGrid.dimensions(count: cameras.count)
        let gap = metrics.token(4)
        ZStack {
            Color.black
            if cameras.isEmpty {
                VStack(spacing: metrics.pt(3)) {
                    Image(systemName: "video.slash.fill").font(.system(size: metrics.pt(14)))
                    Text("No Cameras").font(.system(size: metrics.text(4.4), weight: .semibold))
                    Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                        .font(.clockDigits(size: metrics.pt(12)))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Color.hubSecondaryText)
            } else {
                VStack(spacing: gap) {
                    ForEach(0..<dimensions.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<dimensions.columns, id: \.self) { column in
                                cell(cameras, row * dimensions.columns + column)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .startsOnFirstUse { home.start() }
    }

    @ViewBuilder
    private func cell(_ cameras: [HomeCamera], _ index: Int) -> some View {
        if cameras.indices.contains(index) {
            let camera = cameras[index]
            Button {
                send(.tapInlineControl(.camera(id: camera.id)))
            } label: {
                environment.home.cameraView(id: camera.id, live: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        RoomBadge(text: camera.roomName.isEmpty ? camera.name : camera.roomName)
                            .padding(metrics.token(12))
                            .opacity(density.showsLabels ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: metrics.token(12), style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(camera.name), \(camera.roomName)"))
            .accessibilityIdentifier("camera.\(camera.id)")
        } else {
            Color.clear
        }
    }
}

/// A small glass capsule naming a room, in the corner of a camera picture.
struct RoomBadge: View {
    let text: String
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Text(text)
            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, metrics.token(12))
            .padding(.vertical, metrics.token(6))
            .hubGlass(in: Capsule())
    }
}
