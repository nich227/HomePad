import HomePadCore
import HomePadUICore
import SwiftUI

private struct HubViewerPositionKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> FacePosition?)? = nil
}

extension EnvironmentValues {
    /// Where the viewer is in front of the screen, when something can tell. The wallpaper leans
    /// with it.
    var hubViewerPosition: (@MainActor () -> FacePosition?)? {
        get { self[HubViewerPositionKey.self] }
        set { self[HubViewerPositionKey.self] = newValue }
    }
}

/// The wallpaper behind glass tiles: large soft shapes in one family of color with a lighter
/// sweep across them, drawn in code. The color follows the active profile. In Night Mode there
/// is no wallpaper, only black.
struct HubWallpaper: View {
    /// Nil follows the active profile, and is blue for a guest.
    var tint: RainbowTint?
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubIsNight) private var isNight
    @Environment(\.hubMotion) private var motion
    @Environment(\.hubViewerPosition) private var viewerPosition
    @Environment(HouseholdSession.self) private var session

    var body: some View {
        if isNight {
            Color.black.accessibilityHidden(true)
        } else {
            TimelineView(.periodic(from: .now, by: 0.6)) { _ in
                let position = motion.reducesMotion ? nil : viewerPosition?()
                artwork(lean: CGSize(width: (position?.x ?? 0.5) - 0.5, height: (position?.y ?? 0.5) - 0.5))
                    .animation(.smooth(duration: 1.6), value: position)
            }
            .accessibilityHidden(true)
        }
    }

    private func mixed(_ rgb: (red: Double, green: Double, blue: Double), with other: (Double, Double, Double), _ amount: Double, scale: Double = 1) -> Color {
        Color(
            .sRGB,
            red: (rgb.red * (1 - amount) + other.0 * amount) * scale,
            green: (rgb.green * (1 - amount) + other.1 * amount) * scale,
            blue: (rgb.blue * (1 - amount) + other.2 * amount) * scale,
            opacity: 1
        )
    }

    /// `lean` is how far the viewer is from the middle, -0.5...0.5 each way. Near shapes move
    /// more than far ones, which reads as depth.
    private func artwork(lean: CGSize) -> some View {
        let rgb = (tint ?? session.activeProfile?.tint ?? .blue).rgb
        let indigo = (0.16, 0.12, 0.5)
        let deep = mixed(rgb, with: indigo, 0.62, scale: 0.5)
        let dusk = mixed(rgb, with: indigo, 0.45, scale: 0.78)
        let core = mixed(rgb, with: indigo, 0.2, scale: 0.92)
        let glow = mixed(rgb, with: (1, 1, 1), 0.42)
        let width = metrics.width
        let height = metrics.height
        let unit = metrics.side
        let shiftX = Float(lean.width) * 0.1
        let shiftY = Float(lean.height) * 0.1
        return ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.52 + shiftX, 0.46 + shiftY], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    dusk, core, glow,
                    deep, core, dusk,
                    deep, dusk, deep,
                ]
            )
            Ellipse()
                .fill(deep.opacity(0.75))
                .frame(width: width * 0.95, height: height * 0.8)
                .rotationEffect(.degrees(-24))
                .offset(x: width * 0.3 - lean.width * unit * 0.05, y: height * 0.42 - lean.height * unit * 0.05)
                .blur(radius: unit * 0.035)
            Ellipse()
                .fill(core.opacity(0.7))
                .frame(width: width * 0.8, height: height * 0.75)
                .rotationEffect(.degrees(-30))
                .offset(x: -width * 0.32 - lean.width * unit * 0.09, y: -height * 0.34 - lean.height * unit * 0.09)
                .blur(radius: unit * 0.03)
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .frame(width: max(width, height) * 1.5, height: unit * 0.34)
                .rotationEffect(.degrees(-26))
                .offset(x: width * 0.06 - lean.width * unit * 0.14, y: -height * 0.08 - lean.height * unit * 0.14)
                .blur(radius: unit * 0.045)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

private struct TilePlacementKey: LayoutValueKey {
    static let defaultValue: TilePlacement? = nil
}

extension View {
    /// Where this tile sits on a `TileBoard`.
    func tile(_ placement: TilePlacement) -> some View {
        layoutValue(key: TilePlacementKey.self, value: placement)
    }
}

/// Lays tiles out on a grid of equal cells. Each tile says which cells it covers.
struct TileBoard: Layout {
    let grid: TileGrid
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            guard let placement = subview[TilePlacementKey.self] else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            let frame = placement.frame(in: grid, width: Double(bounds.width), height: Double(bounds.height), gap: Double(gap))
            subview.place(
                at: CGPoint(x: bounds.minX + frame.x, y: bounds.minY + frame.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

/// The round badge in the corner of a tile that holds its glyph.
struct TileBadge: View {
    let symbol: String
    var isOn = false
    var points: Double = DesignTokens.iconBadge
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        let side = metrics.token(points)
        Image(systemName: symbol)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.white)
            .frame(width: side, height: side)
            .background(Circle().fill(isOn ? Color.black.opacity(0.82) : Color.white.opacity(0.2)))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// A tile's two lines of text: a semibold title and a quieter subtitle. The subtitle follows
/// the density: gone across the room, soft on approach, full within reach.
struct TileCaption: View {
    let title: String
    let subtitle: String
    var isOn = false
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density

    var body: some View {
        let ink: Color = isOn ? Color(white: 0.08) : .white
        VStack(alignment: .leading, spacing: metrics.token(1)) {
            Text(title)
                .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                .foregroundStyle(ink)
            Text(subtitle)
                .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                .foregroundStyle(ink.opacity(DesignTokens.subtitleOpacity))
                .opacity(density.showsLabels ? 1 : 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
