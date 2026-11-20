import HomePadCore
import HomePadUICore
import SwiftUI

/// The home, room by room: a bar of rooms across the top, the room's thermostat as a large
/// tile, and its cameras, scenes, and accessories as glass tiles over the wallpaper. A tap
/// switches a tile, a held press opens its slider, and the thermostat opens its dial.
struct HomeApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMayRunScenes) private var mayRunScenes
    @Environment(\.hubAudience) private var audience
    @Environment(\.hubMotion) private var motion
    @Environment(HubEnvironment.self) private var environment
    /// Nil shows the whole home.
    @State private var room: String?
    @Namespace private var roomGlass

    var body: some View {
        let home = environment.home
        ZStack {
            HubWallpaper()
            VStack(spacing: metrics.gutter) {
                header(home.snapshot)
                switch home.access {
                case .ready:
                    content(home.snapshot)
                case .denied:
                    HubEmptyState(
                        symbol: "house.fill",
                        title: "Home Access Is Off",
                        message: "To control lights, scenes, and cameras from here, allow Home access in Settings.",
                        tint: Color(RainbowTint.orange)
                    ) {
                        HubSettingsButton()
                    }
                case .noHomes:
                    HubEmptyState(
                        symbol: "house.fill",
                        title: "No Home Yet",
                        message: "Set up a home in the Home app on this iPad. Its accessories and scenes will appear here.",
                        tint: Color(RainbowTint.orange)
                    )
                case .unknown:
                    HubEmptyState(
                        symbol: "house.fill",
                        title: "Home",
                        message: "Looking for your home.",
                        tint: Color(RainbowTint.orange)
                    )
                }
            }
            .padding(.horizontal, metrics.margin)
            .padding(.top, metrics.topEdge)
            .padding(.bottom, metrics.bottomBar)
        }
        .environment(\.faceDensity, .detailed)
        .startsOnFirstUse { home.start() }
        .animation(motion.spring, value: room)
    }

    /// The close button and the rooms. The rooms scroll sideways only when there are more than
    /// fit, which is the one place the hub lets a row do that.
    private func header(_ snapshot: HomeSnapshot) -> some View {
        HStack(spacing: metrics.gutter) {
            GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
            let pills = GlassEffectContainer(spacing: metrics.token(6)) {
                HStack(spacing: metrics.token(6)) {
                    roomPill(nil, title: snapshot.homeName.isEmpty ? String(localized: "Home") : snapshot.homeName)
                    ForEach(snapshot.roomNames, id: \.self) { name in
                        roomPill(name, title: name)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                pills
                ScrollView(.horizontal) { pills }
                    .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .frame(height: metrics.chromeHeight)
    }

    private func roomPill(_ name: String?, title: String) -> some View {
        let isSelected = room == name
        return Button {
            room = name
        } label: {
            Text(title)
                .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle + 1), weight: .semibold))
                .foregroundStyle(isSelected ? Color(white: 0.08) : .white)
                .lineLimit(1)
                .padding(.horizontal, metrics.token(16))
                .frame(height: metrics.chromeHeight)
                .background {
                    if isSelected {
                        Capsule().fill(.white)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Capsule(), tint: isSelected ? .white : nil, interactive: true)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("home.room.\(name ?? "all")")
    }

    /// On a wide screen the thermostat keeps the leading part and the tiles scroll beside it;
    /// on a tall one it sits above them.
    @ViewBuilder
    private func content(_ snapshot: HomeSnapshot) -> some View {
        let thermostat = snapshot.thermostats.first { room == nil || $0.roomName == room }
        let tiles = snapshot.tiles(inRoom: room)
        if metrics.isLandscape {
            HStack(alignment: .top, spacing: metrics.gutter) {
                if let thermostat {
                    ThermostatTile(thermostat: thermostat)
                        .frame(width: metrics.width * 0.3)
                        .transition(.opacity)
                }
                grid(tiles, snapshot: snapshot, width: metrics.width - metrics.margin * 2 - (thermostat == nil ? 0 : metrics.width * 0.3 + metrics.gutter))
            }
        } else {
            VStack(spacing: metrics.gutter) {
                if let thermostat {
                    ThermostatTile(thermostat: thermostat)
                        .frame(height: metrics.token(210))
                        .transition(.opacity)
                }
                grid(tiles, snapshot: snapshot, width: metrics.width - metrics.margin * 2)
            }
        }
    }

    private func grid(_ tiles: [HomeTile], snapshot: HomeSnapshot, width: CGFloat) -> some View {
        let count = max(2, Int((width / metrics.token(128)).rounded(.down)))
        let cell = (width - metrics.gutter * CGFloat(count - 1)) / CGFloat(count)
        return ScrollView {
            GlassEffectContainer(spacing: metrics.gutter) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: metrics.gutter), count: count), spacing: metrics.gutter) {
                    ForEach(tiles) { tile in
                        HomeTileView(tile: tile)
                            .frame(width: cell, height: cell * 0.82)
                    }
                }
            }
            if tiles.isEmpty {
                Text("Nothing in this room yet.")
                    .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .medium))
                    .foregroundStyle(Color.hubSecondaryText)
                    .padding(.top, metrics.token(40))
            }
            if !mayRunScenes, room == nil, !snapshot.scenes.isEmpty {
                Label(
                    audience.isGuest ? "Scenes run only for household members the hub recognizes." : "Scenes run when the hub recognizes your face.",
                    systemImage: "lock.fill"
                )
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .medium))
                    .foregroundStyle(Color.hubSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, metrics.token(6))
                    .accessibilityIdentifier("home.scenesLocked")
            }
        }
        .scrollIndicators(.hidden)
        .frame(width: width)
    }
}
