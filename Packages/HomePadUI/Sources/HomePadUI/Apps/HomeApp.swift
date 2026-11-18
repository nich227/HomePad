import HomePadCore
import HomePadUICore
import SwiftUI

/// The home on a light three-column grid: a clock, the thermostat, scenes, accessories, and
/// cameras. Lit tiles mean the accessory is on.
struct HomeApp: View {
    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(HubEnvironment.self) private var environment
    @State private var liveCameraID: String?

    var body: some View {
        let home = environment.home
        ZStack {
            AppScreen(title: "Home", background: .white, ink: Color(white: 0.15), onClose: onClose) {
                switch home.access {
                case .ready:
                    grid(home.snapshot)
                case .denied:
                    message("HomePad needs access to your home. Allow Home access in Settings.", showsSettings: true)
                case .noHomes:
                    message("No home is set up. Add one in the Home app.", showsSettings: false)
                case .unknown:
                    ProgressView()
                }
            }
            if let liveCameraID {
                ZStack(alignment: .topLeading) {
                    Color.black
                    home.cameraView(id: liveCameraID, live: true)
                    GlassCircleButton(symbol: "xmark", label: "Close Camera") { self.liveCameraID = nil }
                        .padding(metrics.pt(4))
                }
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .light)
        .onAppear { home.start() }
        .animation(.smooth(duration: 0.3), value: liveCameraID)
    }

    private func message(_ text: LocalizedStringKey, showsSettings: Bool) -> some View {
        VStack(spacing: metrics.pt(3)) {
            Image(systemName: "house.fill")
                .font(.system(size: metrics.pt(14)))
                .foregroundStyle(Color(RainbowTint.orange))
            Text(text)
                .font(.system(size: metrics.text(3.6), weight: .semibold))
                .foregroundStyle(Color(white: 0.2))
                .multilineTextAlignment(.center)
            if showsSettings {
                OpenSettingsButton()
                    .font(.system(size: metrics.text(3.2), weight: .semibold))
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(metrics.pt(8))
    }

    private func grid(_ snapshot: HomeSnapshot) -> some View {
        let gap = metrics.pt(2.2)
        let cell = (metrics.side - metrics.pt(4) * 2 - gap * 2) / 3
        let tiles: [HomeTile] = snapshot.cameras.map(HomeTile.camera) + snapshot.scenes.map(HomeTile.scene) + snapshot.accessories.map(HomeTile.accessory)
        return ScrollView {
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { timeline in
                        AnalogDial(date: timeline.date, markers: .numerals, inkColor: Color(red: 0.35, green: 0.3, blue: 0.6), secondColor: Color(red: 0.35, green: 0.3, blue: 0.6))
                    }
                    .frame(width: cell, height: cell)
                    if let thermostat = snapshot.thermostats.first {
                        ThermostatTile(thermostat: thermostat, style: .light, numberSize: 13)
                            .frame(height: cell)
                    } else {
                        RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
                            .fill(Color(white: 0.9))
                            .overlay(Image(systemName: "house.fill").font(.system(size: metrics.pt(10))).foregroundStyle(Color(white: 0.45)))
                            .frame(height: cell)
                            .accessibilityHidden(true)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 3), spacing: gap) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func tileView(_ tile: HomeTile) -> some View {
        switch tile {
        case .camera(let camera):
            HomeTileView(tile: tile, style: .light)
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
            HomeTileView(tile: tile, style: .light)
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
            HomeTileView(tile: tile, style: .light)
        }
    }
}
