import HomePadCore
import HomePadUICore
import SwiftUI

/// The home on a three-column grid of tiles: a clock, the thermostat, cameras, scenes, and
/// accessories. A lit tile means the accessory is on.
struct HomeApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMayRunScenes) private var mayRunScenes
    @Environment(HubEnvironment.self) private var environment
    @State private var liveCameraID: String?

    var body: some View {
        let home = environment.home
        ZStack {
            AppScreen(title: "Home", onClose: onClose) {
                switch home.access {
                case .ready:
                    grid(home.snapshot)
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
            if let liveCameraID {
                ZStack(alignment: .topLeading) {
                    Color.black
                    home.cameraView(id: liveCameraID, live: true)
                    GlassCircleButton(symbol: "xmark", label: "Close Camera") { self.liveCameraID = nil }
                        .padding(metrics.pt(4))
                }
                .transition(.opacity)
            }
        }
        .startsOnFirstUse { home.start() }
        .animation(.smooth(duration: 0.3), value: liveCameraID)
    }

    private func grid(_ snapshot: HomeSnapshot) -> some View {
        let gap = metrics.pt(2.2)
        let cell = (metrics.side - metrics.pt(4) * 2 - gap * 2) / 3
        let tiles: [HomeTile] = snapshot.cameras.map(HomeTile.camera) + snapshot.scenes.map(HomeTile.scene) + snapshot.accessories.map(HomeTile.accessory)
        return ScrollView {
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                        AnalogDial(date: timeline.date, markers: .numerals)
                    }
                    .frame(width: cell, height: cell)
                    if let thermostat = snapshot.thermostats.first {
                        ThermostatTile(thermostat: thermostat, style: .solid, numberSize: 15)
                            .frame(height: cell)
                    } else {
                        RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
                            .fill(Color.hubTileFill)
                            .overlay(
                                VStack(spacing: metrics.pt(1)) {
                                    Image(systemName: "house.fill").font(.system(size: metrics.pt(9)))
                                    Text(snapshot.homeName).font(.system(size: metrics.text(3.2), weight: .semibold))
                                }
                                .foregroundStyle(.white)
                            )
                            .frame(height: cell)
                            .accessibilityElement(children: .combine)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 3), spacing: gap) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                            .frame(width: cell, height: cell)
                    }
                }
                if !mayRunScenes, !snapshot.scenes.isEmpty {
                    Label("Scenes run only for household members the hub recognizes.", systemImage: "lock.fill")
                        .font(.system(size: metrics.text(2.9), weight: .medium))
                        .foregroundStyle(Color.hubSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, metrics.pt(1))
                        .accessibilityIdentifier("home.scenesLocked")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func tileView(_ tile: HomeTile) -> some View {
        switch tile {
        case .camera(let camera):
            HomeTileView(tile: tile, style: .solid)
                .allowsHitTesting(false)
                .overlay {
                    Button {
                        liveCameraID = camera.id
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Show \(camera.name) live"))
                }
        case .accessory(let accessory) where accessory.brightness != nil:
            HomeTileView(tile: tile, style: .solid)
                .contextMenu {
                    ForEach([100, 75, 50, 25], id: \.self) { level in
                        Button {
                            Task { await environment.home.setBrightness(level, accessoryID: accessory.id) }
                        } label: {
                            Text(verbatim: "\(level)%")
                        }
                    }
                    Button("Off") {
                        Task { await environment.home.setBrightness(0, accessoryID: accessory.id) }
                    }
                }
        default:
            HomeTileView(tile: tile, style: .solid)
        }
    }
}
