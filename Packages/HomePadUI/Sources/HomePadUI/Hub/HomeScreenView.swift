import HomePadCore
import HomePadUICore
import SwiftUI

/// The app view: a greeting, the active profile, and a four-column grid of app icons and
/// two by two widgets over the blurred face.
struct HomeScreenView: View {
    let layout: HomeScreenLayout
    let profileCount: Int
    /// Nil when the status is already shown beside the canvas.
    let recognitionIndicator: (@MainActor () -> AnyView)?
    let onOpen: (HubApp) -> Void
    /// Runs the device's biometrics, then opens the app if that unlocked it.
    let onUnlock: (HubApp) -> Void
    /// False when a button beside the canvas already leads back to the face.
    let showsFaceButton: Bool
    let onMove: (String, String) -> Void
    let onProfile: () -> Void
    let onClose: () -> Void

    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.hubAudience) private var audience
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock
    @Environment(\.calendar) private var calendar
    @Environment(HouseholdSession.self) private var session

    private static let columns = 4

    private var visibleItems: [HomeScreenItem] {
        layout.items.filter { item in
            if case .widget = item, !preferences.homeShowsWidgets { return false }
            return VisibilityPolicy.visibility(for: item.access, context: audience) != .hidden
        }
    }

    var body: some View {
        let margin = metrics.pt(8.5)
        let gapX = metrics.pt(4.2)
        let gapY = metrics.pt(2.6)
        let cell = (metrics.side - margin * 2 - gapX * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        let rowHeight = metrics.pt(14.5) + metrics.text(5.4)
        let packed = HomeGridPacker.pack(visibleItems, columns: Self.columns)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.pt(5)) {
                header
                if VisibilityPolicy.needsSetupHint(profileCount: profileCount, setupMode: preferences.setupMode) {
                    setupNote
                }
                HomeGridLayout(packed: packed, columns: Self.columns, cell: cell, rowHeight: rowHeight, gapX: gapX, gapY: gapY) {
                    ForEach(packed.placements) { placement in
                        itemView(placement.item)
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, metrics.pt(9))
            .padding(.bottom, metrics.pt(12))
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("hub.homeScreen")
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < -metrics.pt(13)
        } action: { _, pulledPastTop in
            if pulledPastTop {
                onClose()
            }
        }
        .overlay(alignment: .bottom) {
            if showsFaceButton {
                Button(action: onClose) {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: metrics.pt(5), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: metrics.pt(16), height: metrics.pt(6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Show Face")
                .accessibilityIdentifier("hub.showFace")
                .padding(.bottom, metrics.pt(1.5))
            }
        }
    }

    private var header: some View {
        let hour = calendar.component(.hour, from: Date())
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: metrics.pt(0.4)) {
                Text(greeting(TimeTextPolicy.greeting(forHour: hour)))
                    .font(.system(size: metrics.text(3.5), weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                Text(session.activeProfile?.name ?? String(localized: "Guest"))
                    .font(.system(size: metrics.text(3.5), weight: .bold))
                    .foregroundStyle(.white)
            }
            .textCase(.uppercase)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer()
            if let recognitionIndicator {
                recognitionIndicator()
            }
            Button(action: onProfile) {
                ProfileAvatar(profile: session.activeProfile, diameter: metrics.pt(9.5))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(session.activeProfile.map { Text("Switch profile. Current: \($0.name)") } ?? Text("Switch profile. Current: Guest"))
            .accessibilityIdentifier("hub.profile")
        }
    }

    private func greeting(_ part: DayPart) -> LocalizedStringKey {
        switch part {
        case .morning: "Good morning,"
        case .afternoon: "Good afternoon,"
        case .evening: "Good evening,"
        case .night: "Good night,"
        }
    }

    private var setupNote: some View {
        VStack(alignment: .leading, spacing: metrics.pt(2)) {
            Text("No one is set up yet. To add people, turn on Setup Mode in Settings.")
                .font(.system(size: metrics.text(3.1), weight: .medium))
                .foregroundStyle(.white)
            HubSettingsButton()
        }
        .padding(metrics.pt(3.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubTile(metrics)
    }

    @ViewBuilder
    private func itemView(_ item: HomeScreenItem) -> some View {
        let visibility = VisibilityPolicy.visibility(for: item.access, context: audience)
        let tap = VisibilityPolicy.tapAction(for: item.access, context: audience, isDeviceUnlockOffered: showsDeviceUnlock)
        let act: (HubApp) -> Void = { app in
            switch tap {
            case .open: onOpen(app)
            case .requestUnlock: onUnlock(app)
            case .none: break
            }
        }
        Group {
            switch item {
            case .app(let app):
                AppIconView(app: app, isRedacted: visibility == .redacted, offersUnlock: tap == .requestUnlock) { act(app) }
            case .widget(let widget):
                HomeWidgetView(kind: widget, isRedacted: visibility == .redacted, offersUnlock: tap == .requestUnlock) { act(widget.app) }
            }
        }
        .draggable(item.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first else { return false }
            onMove(dragged, item.id)
            return true
        }
    }
}

extension AppIconView {
    fileprivate var lockedHint: Text {
        if offersUnlock { return Text("Locked. Unlock with Touch ID to open.") }
        return isRedacted ? Text("Locked until the hub recognizes its owner.") : Text(verbatim: "")
    }
}

/// Puts each icon and widget in its grid cell. A real layout, so each item's frame is where it
/// is drawn and scroll visibility can be judged per item.
struct HomeGridLayout: Layout {
    let packed: HomeGridPacker.Result
    let columns: Int
    let cell: CGFloat
    let rowHeight: CGFloat
    let gapX: CGFloat
    let gapY: CGFloat

    private func size(span: Int) -> CGSize {
        let count = CGFloat(span)
        return CGSize(width: cell * count + gapX * (count - 1), height: rowHeight * count + gapY * (count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = CGFloat(columns)
        let rows = CGFloat(packed.rowCount)
        return CGSize(width: cell * columns + gapX * (columns - 1), height: max(0, rows * (rowHeight + gapY) - gapY))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, placement) in zip(subviews, packed.placements) {
            let origin = CGPoint(
                x: bounds.minX + CGFloat(placement.column) * (cell + gapX),
                y: bounds.minY + CGFloat(placement.row) * (rowHeight + gapY)
            )
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size(span: placement.span)))
        }
    }
}

/// An app icon: a rounded square in the app's color with its symbol, and the name underneath.
struct AppIconView: View {
    let app: HubApp
    let isRedacted: Bool
    /// The icon is locked, and tapping it asks for the device's biometrics.
    var offersUnlock = false
    let action: () -> Void
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        let size = metrics.pt(14.5)
        let base = app.tint.map { Color($0) } ?? Color(white: 0.34)
        Button(action: action) {
            VStack(spacing: metrics.pt(1)) {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .fill(LinearGradient(colors: [base.opacity(0.92), base], startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                        )
                    Image(systemName: app.symbolName)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .saturation(isRedacted ? 0 : 1)
                .opacity(isRedacted ? 0.5 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if isRedacted {
                        Image(systemName: offersUnlock ? "touchid" : "lock.fill")
                            .font(.system(size: size * (offersUnlock ? 0.3 : 0.2), weight: .bold))
                            .foregroundStyle(offersUnlock ? Color(RainbowTint.red) : .white)
                            .padding(size * 0.07)
                            .background(Circle().fill(offersUnlock ? Color.white : Color.black.opacity(0.6)))
                            .offset(x: size * 0.08, y: size * 0.08)
                    }
                }
                Text(app.title)
                    .font(.system(size: metrics.text(2.9), weight: .medium))
                    .foregroundStyle(.white.opacity(isRedacted ? 0.5 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .shadow(color: .black.opacity(0.35), radius: metrics.pt(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRedacted && !offersUnlock)
        .hoverEffect(.lift)
        .accessibilityHint(lockedHint)
        .accessibilityIdentifier("app.\(app.rawValue)")
    }
}
