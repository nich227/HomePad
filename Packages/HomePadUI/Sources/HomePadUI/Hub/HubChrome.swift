import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadUICore
import SwiftUI

/// The pill at the top center of a face: the live things, one line when compact, a card when
/// tapped. The glass grows from the pill into the card in place, and shrinks back.
struct LivePillView: View {
    let items: [LivePillItem]
    /// The most room the compact pill may take, so it never runs under the status beside it.
    var maxWidth: CGFloat = .infinity
    /// Optional apps that have something behind them right now.
    var availableApps: Set<HubApp> = []
    @Binding var isExpanded: Bool
    let onOpen: (HubApp) -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMotion) private var motion
    @Environment(HubEnvironment.self) private var environment
    @Environment(HouseholdSession.self) private var session
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer {
            if let first = items.first {
                if isExpanded {
                    card
                        .glassEffectID("pill", in: glass)
                        .transition(.opacity)
                } else {
                    compact(first)
                        .glassEffectID("pill", in: glass)
                        .transition(.opacity)
                }
            }
        }
        .animation(motion.spring, value: isExpanded)
        .animation(motion.spring, value: items.map(\.id))
    }

    private func compact(_ item: LivePillItem) -> some View {
        let limit = max(min(metrics.token(DesignTokens.pillWidth), maxWidth), metrics.chromeHeight * 1.6)
        return Button {
            isExpanded = true
        } label: {
            HStack(spacing: metrics.token(8)) {
                glyph(item, side: metrics.token(26))
                Text(item.title)
                    .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: item.kind == .timer))
                    .layoutPriority(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                        .foregroundStyle(Color.hubSecondaryText)
                }
                if items.count > 1 {
                    Text(verbatim: "+\(items.count - 1)")
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                        .foregroundStyle(Color.hubSecondaryText)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, metrics.token(14))
            .frame(minWidth: min(metrics.token(120), limit), maxWidth: limit)
            .frame(height: max(metrics.token(DesignTokens.pillHeight), HubMetrics.minimumTouchSide))
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hubGlass(in: Capsule(), interactive: true)
        .accessibilityLabel("Live activities")
        .accessibilityValue(Text(verbatim: items.map { "\($0.title) \($0.detail)" }.joined(separator: ", ")))
        .accessibilityIdentifier("hub.pill")
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.tileRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: metrics.token(10)) {
            ForEach(items) { item in
                row(item)
            }
        }
        .padding(metrics.token(16))
        .frame(width: min(metrics.token(DesignTokens.pillCardWidth), metrics.width - metrics.margin * 2), alignment: .leading)
        .hubGlass(in: shape)
        .contentShape(shape)
        .onTapGesture { isExpanded = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.pillCard")
    }

    private func row(_ item: LivePillItem) -> some View {
        HStack(spacing: metrics.token(12)) {
            glyph(item, side: metrics.token(40))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: metrics.textToken(item.kind == .timer ? 30 : 20), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: item.kind == .timer))
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                        .foregroundStyle(Color.hubSecondaryText)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            controls(item)
        }
    }

    @ViewBuilder
    private func glyph(_ item: LivePillItem, side: CGFloat) -> some View {
        if item.kind == .recognized {
            ProfileAvatar(profile: session.activeProfile, diameter: side)
        } else if item.kind == .nowPlaying {
            ArtworkView(image: environment.music.artwork, cornerRadius: side * 0.22)
                .frame(width: side, height: side)
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: side * 0.6, weight: .semibold))
                .foregroundStyle(item.kind == .timer ? Color(RainbowTint.orange) : .white)
                .symbolEffect(.pulse, options: .repeating, isActive: item.kind == .timer && !motion.reducesMotion)
                .frame(width: side, height: side)
        }
    }

    @ViewBuilder
    private func controls(_ item: LivePillItem) -> some View {
        switch item.kind {
        case .nowPlaying:
            HStack(spacing: metrics.token(6)) {
                GlassCircleButton(symbol: "backward.fill", label: "Previous", size: 8, action: environment.music.skipToPrevious)
                GlassCircleButton(
                    symbol: environment.music.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                    label: "Play or Pause",
                    size: 8,
                    identifier: "pill.playPause",
                    action: environment.music.togglePlayPause
                )
                GlassCircleButton(symbol: "forward.fill", label: "Next", size: 8, action: environment.music.skipToNext)
            }
        case .recognized:
            EmptyView()
        default:
            if let app = item.destination(available: availableApps) {
                GlassCircleButton(symbol: "arrow.up.right", label: "Open", size: 8, identifier: "pill.open.\(item.kind.rawValue)") {
                    isExpanded = false
                    onOpen(app)
                }
            }
        }
    }
}

/// Who is in front of the hub, in the top trailing corner: the recognition status another
/// package draws, the Touch ID and assistant controls when they apply, and the avatar. A tap
/// on the avatar opens the control center, which a swipe down from this corner also does.
struct StatusCluster: View {
    let profile: HouseholdProfile?
    let isSomeonePresent: Bool
    let indicator: @MainActor () -> AnyView
    let showsAssistant: Bool
    let onControlCenter: () -> Void
    let onUnlock: () -> Void
    let onAssistant: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.faceDensity) private var density
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock

    /// The name shows on approach, where there is room for it beside the pill.
    private var showsName: Bool {
        density.showsLabels && metrics.isLandscape && metrics.width >= 600
    }

    var body: some View {
        let side = metrics.chromeHeight
        HStack(spacing: metrics.token(6)) {
            if showsAssistant {
                small("sparkles", label: "Assistant", identifier: "hub.assistant", side: side, action: onAssistant)
            }
            if showsDeviceUnlock {
                small("touchid", label: "Unlock with Touch ID", identifier: "hub.deviceUnlock", side: side, tint: Color(RainbowTint.red), action: onUnlock)
            }
            Button(action: onControlCenter) {
                HStack(spacing: metrics.token(8)) {
                    indicator()
                        .frame(maxHeight: side * 0.7)
                        .fixedSize()
                    if showsName {
                        Text(profile?.name ?? String(localized: "Guest"))
                            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    ZStack {
                        if isSomeonePresent {
                            HomePadAnimationView(.presencePulse, loop: true)
                                .frame(width: side * 0.9, height: side * 0.9)
                        }
                        ProfileAvatar(profile: profile, diameter: side * 0.68)
                    }
                    .frame(width: side * 0.8, height: side * 0.8)
                }
                .padding(.leading, metrics.token(showsName ? 12 : 4))
                .padding(.trailing, metrics.token(4))
                .frame(height: side)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hubGlass(in: Capsule(), interactive: true)
            .hoverEffect(.highlight)
            .accessibilityLabel(profile.map { Text("Profile: \($0.name)") } ?? Text("Profile: Guest"))
            .accessibilityHint("Opens the control center.")
            .accessibilityIdentifier("hub.profile")
        }
    }

    private func small(_ symbol: String, label: LocalizedStringKey, identifier: String, side: CGFloat, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.5, weight: .semibold))
                .foregroundStyle(tint)
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

/// The bar at the bottom edge. A swipe up from here, or a tap, goes to the Home Screen; from
/// the Home Screen a tap goes back to the face.
struct HomeBar: View {
    let leadsToFace: Bool
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(.white.opacity(0.7))
                .frame(width: metrics.token(134), height: max(metrics.token(5), 4))
                .frame(width: metrics.token(220), height: max(metrics.bottomBar, HubMetrics.minimumTouchSide), alignment: .bottom)
                .padding(.bottom, metrics.token(8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(leadsToFace ? "Show Face" : "Show Home Screen")
        .accessibilityIdentifier(leadsToFace ? "hub.showFace" : "hub.showHomeScreen")
    }
}

/// A dim, heavily blurred layer between what is showing and an overlay. A tap on it closes
/// the overlay. In Night Mode it is plain black.
struct OverlayScrim: View {
    let onDismiss: () -> Void
    @Environment(\.hubIsNight) private var isNight
    @Environment(\.hubSolidGlass) private var solidGlass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if isNight {
                Color.black.opacity(0.92)
            } else if solidGlass || reduceTransparency {
                Color.black.opacity(0.86)
            } else {
                Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityLabel("Close")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("hub.scrim")
    }
}
