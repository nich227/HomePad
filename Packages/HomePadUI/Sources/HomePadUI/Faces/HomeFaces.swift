import HomePadCore
import HomePadUICore
import SwiftUI

/// How a home tile is drawn: glass over a wallpaper on faces, flat fills in the Home app.
enum HomeTileStyle {
    case glass
    case light
}

/// One small square tile: an icon, a name, and where it is. Tapping acts on it.
struct HomeTileView: View {
    let tile: HomeTile
    let style: HomeTileStyle
    var showsSubtitle = true
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubAudience) private var audience
    @Environment(HubEnvironment.self) private var environment

    private var isActive: Bool {
        if case .accessory(let accessory) = tile { return accessory.isOn && accessory.kind != .lock }
        return false
    }

    private var content: (symbol: String, title: String, subtitle: String) {
        switch tile {
        case .accessory(let accessory):
            let symbol = accessory.kind == .lock ? (accessory.isOn ? "lock.fill" : "lock.open.fill") : accessory.kind.symbolName
            return (symbol, accessory.name, accessory.roomName)
        case .scene(let scene):
            return (scene.symbolName, scene.name, String(localized: "Scene"))
        case .camera(let camera):
            return ("video.fill", camera.name, camera.roomName)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
        Button(action: activate) {
            Group {
                if case .camera(let camera) = tile {
                    environment.home.cameraView(id: camera.id, live: false)
                } else {
                    label
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .modifier(HomeTileBackground(style: style, isActive: isActive, shape: shape))
        .clipShape(shape)
        .hoverEffect(.highlight)
        .accessibilityLabel(Text(verbatim: "\(content.title), \(content.subtitle)"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var label: some View {
        let info = content
        let tint = Color(RainbowTint.purple)
        let primary: Color = style == .glass ? .white : (isActive ? tint : Color(white: 0.3))
        return VStack(spacing: metrics.pt(0.6)) {
            Image(systemName: info.symbol)
                .font(.system(size: metrics.pt(7.5)))
                .frame(height: metrics.pt(11))
                .foregroundStyle(primary.opacity(style == .glass && !isActive ? 0.92 : 1))
            Text(info.title)
                .font(.system(size: metrics.text(2.9), weight: .semibold))
                .foregroundStyle(primary)
            if showsSubtitle {
                Text(info.subtitle)
                    .font(.system(size: metrics.text(2.7)))
                    .foregroundStyle(primary.opacity(0.62))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, metrics.pt(1.5))
    }

    private func activate() {
        switch tile {
        case .accessory(let accessory):
            guard HomeControlPolicy.mayOperate(accessory, turningOn: !accessory.isOn, isGuest: audience.isGuest) else { return }
            Task { await environment.home.setPower(!accessory.isOn, accessoryID: accessory.id) }
        case .scene(let scene):
            Task { await environment.home.runScene(id: scene.id) }
        case .camera:
            break
        }
    }
}

private struct HomeTileBackground<S: Shape>: ViewModifier {
    let style: HomeTileStyle
    let isActive: Bool
    let shape: S

    func body(content: Content) -> some View {
        switch style {
        case .glass:
            content.hubGlass(in: shape, tint: isActive ? Color.white.opacity(0.18) : nil, interactive: true)
        case .light:
            content.background(shape.fill(isActive ? Color(RainbowTint.purple).opacity(0.28) : Color(white: 0.9)))
        }
    }
}

/// The large thermostat tile: the target temperature with down and up controls.
struct ThermostatTile: View {
    let thermostat: HomeThermostat
    let style: HomeTileStyle
    var numberSize: CGFloat = 25
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let ink: Color = style == .glass ? .white : Color(white: 0.2)
        let shape = RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: "\(units.temperature.rounded(fromCelsius: thermostat.targetCelsius))")
                .font(.system(size: metrics.pt(numberSize), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                step(-1, symbol: "chevron.down", label: "Lower Temperature", ink: ink)
                Spacer(minLength: 0)
                VStack(spacing: metrics.pt(0.3)) {
                    Text(thermostat.name)
                        .font(.system(size: metrics.text(2.9), weight: .bold))
                        .foregroundStyle(ink)
                    Text(verbatim: "\(thermostat.roomName) \u{00B7} \(units.degrees(thermostat.currentCelsius))")
                        .font(.system(size: metrics.text(2.7)))
                        .foregroundStyle(ink.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                step(1, symbol: "chevron.up", label: "Raise Temperature", ink: ink)
            }
            .padding(.horizontal, metrics.pt(3))
            .padding(.bottom, metrics.pt(4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HomeTileBackground(style: style, isActive: false, shape: shape))
        .accessibilityElement(children: .contain)
    }

    private func step(_ direction: Int, symbol: String, label: LocalizedStringKey, ink: Color) -> some View {
        Button {
            let target = ThermostatMath.stepped(targetCelsius: thermostat.targetCelsius, direction: direction, unit: units.temperature)
            Task { await environment.home.setTargetTemperature(celsius: target, thermostatID: thermostat.id) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: metrics.pt(4.4), weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: metrics.pt(9), height: metrics.pt(9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Soft abstract shapes in one hue, standing in for a wallpaper behind glass tiles.
struct AbstractWallpaper: View {
    let tint: RainbowTint
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        let color = Color(tint)
        ZStack {
            LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: metrics.pt(90))
                .offset(x: metrics.pt(-26), y: metrics.pt(-30))
            Circle()
                .fill(.black.opacity(0.18))
                .frame(width: metrics.pt(80))
                .offset(x: metrics.pt(34), y: metrics.pt(30))
            RoundedRectangle(cornerRadius: metrics.pt(12), style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: metrics.pt(70), height: metrics.pt(36))
                .rotationEffect(.degrees(-38))
                .offset(x: metrics.pt(20), y: metrics.pt(-18))
        }
        .accessibilityHidden(true)
    }
}

/// Favorite accessories and scenes as glass tiles: a large thermostat, a clock, and four small
/// tiles, on a three by three grid.
struct HomeModularFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session

    var body: some View {
        let home = environment.home
        let gap = metrics.pt(2.4)
        let cell = (metrics.side - metrics.pt(3.2) * 2 - gap * 2) / 3
        let tiles = HomeFavorites.smallTiles(in: home.snapshot, limit: 4)
        let detailed = density == .detailed
        ZStack {
            AbstractWallpaper(tint: session.activeProfile?.tint ?? .blue)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    largeTile(detailed: detailed)
                        .frame(width: cell * 2 + gap, height: cell * 2 + gap)
                    VStack(spacing: gap) {
                        AnalogDial(date: date, markers: .hourTicks, secondColor: .white)
                            .padding(metrics.pt(1))
                            .frame(width: cell, height: cell)
                        small(tiles, 0, detailed: detailed).frame(width: cell, height: cell)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(1..<4, id: \.self) { index in
                        small(tiles, index, detailed: detailed).frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { home.start() }
    }

    @ViewBuilder
    private func largeTile(detailed: Bool) -> some View {
        if let thermostat = environment.home.snapshot.thermostats.first {
            ThermostatTile(thermostat: thermostat, style: .glass, numberSize: detailed ? 25 : 31)
        } else {
            VStack(spacing: metrics.pt(2)) {
                Image(systemName: "house.fill").font(.system(size: metrics.pt(16)))
                Text(homeMessage)
                    .font(.system(size: metrics.text(3.2), weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(metrics.pt(4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hubTile(metrics)
        }
    }

    private var homeMessage: String {
        switch environment.home.access {
        case .ready: environment.home.snapshot.homeName
        case .denied: String(localized: "Allow Home access in Settings")
        case .noHomes: String(localized: "No home is set up")
        case .unknown: String(localized: "Home")
        }
    }

    @ViewBuilder
    private func small(_ tiles: [HomeTile], _ index: Int, detailed: Bool) -> some View {
        if tiles.indices.contains(index) {
            HomeTileView(tile: tiles[index], style: .glass, showsSubtitle: detailed)
        } else {
            Color.clear
        }
    }
}

/// Up to nine cameras in a grid.
struct HomeCameraFace: View {
    let date: Date
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        let home = environment.home
        let cameras = Array(home.snapshot.cameras.prefix(CameraGrid.limit))
        let dimensions = CameraGrid.dimensions(count: cameras.count)
        let gap = metrics.pt(2.4)
        ZStack {
            Color.black
            if cameras.isEmpty {
                VStack(spacing: metrics.pt(3)) {
                    Image(systemName: "video.slash.fill").font(.system(size: metrics.pt(14)))
                    Text("No Cameras").font(.system(size: metrics.text(4.4), weight: .semibold))
                    Text(FaceText.clock(date, calendar: calendar, density: density, units: units).digits)
                        .font(.clockDigits(size: metrics.pt(12)))
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
                .padding(metrics.pt(3.2))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { home.start() }
    }

    @ViewBuilder
    private func cell(_ cameras: [HomeCamera], _ index: Int) -> some View {
        if cameras.indices.contains(index) {
            let camera = cameras[index]
            environment.home.cameraView(id: camera.id, live: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    if density == .detailed {
                        Text(camera.name)
                            .font(.system(size: metrics.text(2.8), weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: metrics.pt(0.5))
                            .padding(metrics.pt(2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "\(camera.name), \(camera.roomName)"))
        } else {
            Color.clear
        }
    }
}
