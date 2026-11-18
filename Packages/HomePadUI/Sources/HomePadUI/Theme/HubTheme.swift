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
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.pt(size * 0.42), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: metrics.pt(size), height: metrics.pt(size))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Circle(), interactive: true)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// A wide glass capsule button with an icon and a title.
struct GlassCapsuleButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color?
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
