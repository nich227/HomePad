import HomePadCore
import HomePadUICore
import SwiftUI
import UIKit

/// Sizes for everything drawn on the square hub canvas. Faces and apps are laid out in hundredths
/// of the canvas side so they keep their proportions on any screen.
struct HubMetrics: Equatable, Sendable {
    var side: CGFloat = 600
    /// Extra scale for reading text, from the Dynamic Type setting.
    var textScale: CGFloat = 1

    func pt(_ units: CGFloat) -> CGFloat {
        side * units / 100
    }

    func text(_ units: CGFloat) -> CGFloat {
        side * units / 100 * textScale
    }

    /// Corner radius shared by tiles and widgets.
    var tileRadius: CGFloat { pt(6) }

    /// The least side of a control, in points, however small the canvas is.
    static let minimumTouchSide: CGFloat = 44
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
    static let hubSecondaryText = Color.white.opacity(0.62)
}

/// Liquid Glass with an opaque fallback when Reduce Transparency is on.
private struct HubGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(tint.map { $0.opacity(0.9) } ?? Color.hubTileFill))
                .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 1))
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
