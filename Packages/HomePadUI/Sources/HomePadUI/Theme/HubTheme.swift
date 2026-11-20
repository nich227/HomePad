import HomePadCore
import HomePadUICore
import SwiftUI
import UIKit

/// Sizes for everything drawn on the hub canvas. Faces and apps are laid out in hundredths of
/// the canvas's shorter side, so they keep their proportions on any screen, and they use the
/// canvas's real width and height to decide how many columns and rows to draw.
struct HubMetrics: Equatable, Sendable {
    var size = CGSize(width: 600, height: 600)
    /// Extra scale for reading text, from the Dynamic Type setting.
    var textScale: CGFloat = 1
    /// How far down the top edge is covered, by a camera housing or the safe area.
    var topObstruction: CGFloat = 0

    init(size: CGSize = CGSize(width: 600, height: 600), textScale: CGFloat = 1, topObstruction: CGFloat = 0) {
        self.size = size
        self.textScale = textScale
        self.topObstruction = topObstruction
    }

    /// A square canvas, for previews and for panes that only need the unit.
    init(side: CGFloat, textScale: CGFloat = 1) {
        self.init(size: CGSize(width: side, height: side), textScale: textScale)
    }

    /// The shorter side. One hundredth of it is the unit everything is measured in.
    var side: CGFloat { min(size.width, size.height) }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    var isLandscape: Bool { size.width > size.height * 1.15 }

    func pt(_ units: CGFloat) -> CGFloat {
        side * units / 100
    }

    func text(_ units: CGFloat) -> CGFloat {
        side * units / 100 * textScale
    }

    /// A design token, given in points on the 544 point reference square.
    func token(_ points: Double) -> CGFloat {
        CGFloat(DesignTokens.scaled(points, side: Double(side)))
    }

    /// A token for text, which also follows the Dynamic Type setting.
    func textToken(_ points: Double) -> CGFloat {
        token(points) * textScale
    }

    /// Space between the canvas edge and its content.
    var margin: CGFloat { token(DesignTokens.outerMargin) }
    /// Space between tiles.
    var gutter: CGFloat { token(DesignTokens.gutter) }
    /// Corner radius shared by tiles and widgets.
    var tileRadius: CGFloat { token(DesignTokens.tileRadius) }

    /// Where the live pill and the status start: the margin, or below whatever covers the top.
    var topEdge: CGFloat { max(margin, topObstruction) }
    /// The height of the pill and of the status beside it.
    var chromeHeight: CGFloat { max(token(DesignTokens.pillHeight), Self.minimumTouchSide) }
    /// Height kept clear at the top of a face for the live pill and the status.
    var topBar: CGFloat { topEdge + chromeHeight + token(8) }
    /// Space kept clear at the bottom for the bar that leads to the Home Screen.
    var bottomBar: CGFloat { token(DesignTokens.outerMargin + 8) }
    /// Where a board of tiles sits inside the canvas.
    var boardInsets: EdgeInsets {
        EdgeInsets(top: topBar, leading: margin, bottom: bottomBar, trailing: margin)
    }

    var boardSize: CGSize {
        CGSize(width: max(0, width - margin * 2), height: max(0, height - topBar - bottomBar))
    }

    /// How many columns a grid drawn `squareCount` wide on a square gets here: the same on a
    /// tall screen, more on a wide one.
    func columns(_ squareCount: Int) -> Int {
        max(squareCount, Int((width / max(side, 1) * CGFloat(squareCount)).rounded(.down)))
    }

    /// The width of one of `count` cells across the canvas, inside `padding` with `gap` between.
    func cell(count: Int, padding: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, (width - padding * 2 - gap * CGFloat(count - 1)) / CGFloat(count))
    }

    /// The least side of a control, in points, however small the canvas is.
    static let minimumTouchSide: CGFloat = 44
}

/// How the shell animates. Reduce Motion replaces movement with a short fade, and a UI test may
/// slow everything down to catch a transition part way.
struct HubMotion: Equatable, Sendable {
    var reducesMotion = false
    var slowdown: Double = 1

    private func paced(_ animation: Animation) -> Animation {
        reducesMotion ? .easeInOut(duration: 0.2) : animation.speed(1 / slowdown)
    }

    /// Moving between surfaces, opening and closing overlays.
    var spring: Animation { paced(.spring(duration: 0.5, bounce: 0.18)) }
    /// A control answering a touch.
    var snappy: Animation { paced(.snappy(duration: 0.3)) }
    /// Slow changes: density, night, wallpaper.
    var gentle: Animation { paced(.smooth(duration: 0.6)) }
}

/// Units after "automatic" has been resolved against the device's region.
struct HubUnits: Equatable, Sendable {
    var hourCycle: HourCycle = .twelve
    var temperature: TemperatureUnit = .fahrenheit

    init(preferences: HubPreferences, locale: Locale = .current) {
        let uses24Hour = locale.hourCycle == .zeroToTwentyThree || locale.hourCycle == .oneToTwentyFour
        hourCycle = preferences.hourCycle.resolved(localeUses24Hour: uses24Hour)
        temperature = preferences.temperatureUnit.resolved(localeUsesFahrenheit: locale.measurementSystem == .us)
    }

    init() {}

    func degrees(_ celsius: Double) -> String {
        "\(temperature.rounded(fromCelsius: celsius))\u{00B0}"
    }
}

extension EnvironmentValues {
    @Entry var hubMetrics = HubMetrics()
    @Entry var hubPreferences = HubPreferences()
    @Entry var hubUnits = HubUnits()
    @Entry var faceDensity: FaceDensity = .detailed
    @Entry var hubAudience = AudienceContext(isGuest: true, isPersonalContentUnlocked: false, setupMode: true)
    /// False while a system permission prompt would land on top of something else, such as the
    /// welcome screen, or while the view asking is not the one in front.
    @Entry var hubMayPrompt = true
    /// Whether the person in front of the hub may run home scenes.
    @Entry var hubMayRunScenes = false
    /// True while a personalized but locked member can unlock with the device's biometrics.
    @Entry var hubShowsDeviceUnlock = false
    /// True while a fold gives the status, timers, and widgets a side of their own, away from
    /// the canvas.
    @Entry var hubChromeIsApart = false
    /// Night Mode: everything red on black, no glass, no wallpaper.
    @Entry var hubIsNight = false
    /// Glass drawn as solid fills: Reduce Transparency, or a UI test standing in for it.
    @Entry var hubSolidGlass = false
    @Entry var hubMotion = HubMotion()
}

/// Starts a service the first time its view is really in use. Starting is what makes the system
/// ask for permission, so it waits until a prompt would make sense to the person.
private struct FirstUseModifier: ViewModifier {
    let isInUse: Bool
    let start: @MainActor () -> Void
    @Environment(\.hubMayPrompt) private var mayPrompt

    func body(content: Content) -> some View {
        content.task(id: mayPrompt && isInUse) {
            if mayPrompt && isInUse {
                start()
            }
        }
    }
}

extension View {
    func startsOnFirstUse(when isInUse: Bool = true, _ start: @escaping @MainActor () -> Void) -> some View {
        modifier(FirstUseModifier(isInUse: isInUse, start: start))
    }
}

extension DynamicTypeSize {
    var hubTextScale: CGFloat {
        switch self {
        case .xSmall, .small: 0.94
        case .medium, .large: 1
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.18
        default: 1.26
        }
    }
}

extension Font {
    /// Clock digits. Monospaced digits keep the time from shifting as it changes.
    static func clockDigits(size: CGFloat, style: ClockFontStyle = .rounded, weight: Font.Weight = .semibold) -> Font {
        let design: Font.Design = switch style {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        case .monospaced: .monospaced
        }
        return .system(size: size, weight: weight, design: design).monospacedDigit()
    }
}

extension Color {
    static let hubTileFill = Color(white: 0.14)
    static let hubSecondaryText = Color.white.opacity(DesignTokens.subtitleOpacity)
    /// The only color of Night Mode.
    static let hubNightRed = Color(.sRGB, red: 1, green: 45.0 / 255, blue: 32.0 / 255, opacity: 1)
    /// The fill of a dimmer and other warm controls.
    static let hubAmber = Color(.sRGB, red: 1, green: 214.0 / 255, blue: 10.0 / 255, opacity: 1)
}

/// Liquid Glass, with a solid fill when transparency is reduced. In Night Mode there is no
/// material at all: a thin outline on black, which the night tint turns red.
private struct HubGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.hubSolidGlass) private var solidGlass
    @Environment(\.hubIsNight) private var isNight

    func body(content: Content) -> some View {
        if isNight {
            content
                .background(shape.fill(Color.black))
                .overlay(shape.stroke(Color.white.opacity(tint == nil ? 0.45 : 1), lineWidth: 1.5))
        } else if reduceTransparency || solidGlass {
            content
                .background(shape.fill(tint.map { $0.opacity(0.92) } ?? Color.hubTileFill))
                .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 1))
        } else {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        }
    }
}

extension View {
    func hubGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(HubGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// The rounded rectangle every tile and widget uses.
    func hubTile(_ metrics: HubMetrics, tint: Color? = nil, interactive: Bool = false) -> some View {
        hubGlass(in: RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// Night Mode for everything inside: one color, red, on black. Applied once at the root so
    /// no view, including one supplied by another package, can escape it. Views that draw a
    /// colored or light background read `hubIsNight` and draw black instead, and wallpapers and
    /// glass switch themselves off; this tint then reduces whatever is left to red.
    func hubNightTint(_ isNight: Bool) -> some View {
        self
            .environment(\.hubIsNight, isNight)
            .hubNightFilter(isNight)
    }

    /// The color part of Night Mode on its own: whatever is drawn is reduced to its brightness
    /// and shown in red. Something that is already red comes out much darker, so a view that
    /// draws itself red for the night is left out of this and trusted to do so.
    func hubNightFilter(_ isNight: Bool) -> some View {
        self
            .grayscale(isNight ? 1 : 0)
            .contrast(isNight ? 1.3 : 1)
            .colorMultiply(isNight ? Color.hubNightRed : .white)
    }
}

/// The round glass control in the corner of full-screen views.
struct GlassCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var size: CGFloat = 9
    var identifier = ""
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        // On a small canvas a round button keeps the least size a finger can press reliably.
        let side = max(metrics.pt(size), HubMetrics.minimumTouchSide)
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Circle(), interactive: true)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// A wide glass capsule button with an icon and a title.
struct GlassCapsuleButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color?
    var identifier = ""
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: metrics.text(3.4), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, metrics.pt(4))
                .frame(maxWidth: .infinity, minHeight: metrics.pt(11.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Capsule(), tint: tint, interactive: true)
        .hoverEffect(.highlight)
        .accessibilityIdentifier(identifier)
    }
}

/// A full-canvas message for when an app has nothing to show: a large symbol, a title, a line
/// of explanation, and room for one action.
struct HubEmptyState<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var tint: Color = .white
    @ViewBuilder let actions: Actions
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.pt(2.4)) {
            Image(systemName: symbol)
                .font(.system(size: metrics.pt(20), weight: .medium))
                .foregroundStyle(tint)
                .frame(height: metrics.pt(26))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: metrics.text(6), weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: metrics.text(3.6), weight: .medium))
                .foregroundStyle(Color.hubSecondaryText)
            actions
                .padding(.top, metrics.pt(2))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, metrics.pt(9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension HubEmptyState where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey, tint: Color = .white) {
        self.init(symbol: symbol, title: title, message: message, tint: tint) { EmptyView() }
    }
}

/// The single route from the app into the system Settings app, where every preference lives.
struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label("Open Settings", systemImage: "gearshape.fill")
        }
    }
}

/// "Open Settings" at the hub's size: a wide glass capsule, like the other actions on the canvas.
struct HubSettingsButton: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        GlassCapsuleButton(title: "Open Settings", symbol: "gearshape.fill", identifier: "hub.openSettings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
        .frame(width: metrics.pt(46))
    }
}

/// A profile's avatar: its symbol on its rainbow tint.
struct ProfileAvatar: View {
    let profile: HouseholdProfile?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(profile.map { Color($0.tint) } ?? Color(white: 0.3))
            Image(systemName: profile?.symbolName ?? "person.fill.questionmark")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(diameter * (profile == nil ? 0.26 : 0.14))
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
