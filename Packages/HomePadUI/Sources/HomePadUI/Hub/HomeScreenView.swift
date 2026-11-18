import HomePadCore
import HomePadUICore
import SwiftUI

/// The app view: a greeting, the active profile, and a four-column grid of app icons and
/// two by two widgets over the blurred face.
struct HomeScreenView: View {
    let layout: HomeScreenLayout
    let profileCount: Int
    let recognitionIndicator: @MainActor () -> AnyView
    let onOpen: (HubApp) -> Void
    let onMove: (String, String) -> Void
    let onProfile: () -> Void
    let onClose: () -> Void

    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.hubAudience) private var audience
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
                ZStack(alignment: .topLeading) {
                    ForEach(packed.placements) { placement in
                        let span = CGFloat(placement.span)
                        itemView(placement.item)
                            .frame(
                                width: cell * span + gapX * (span - 1),
                                height: rowHeight * span + gapY * (span - 1)
                            )
                            .offset(
                                x: CGFloat(placement.column) * (cell + gapX),
                                y: CGFloat(placement.row) * (rowHeight + gapY)
                            )
                    }
                }
                .frame(
                    width: metrics.side - margin * 2,
                    height: max(0, CGFloat(packed.rowCount) * (rowHeight + gapY) - gapY),
                    alignment: .topLeading
                )
            }
            .padding(.horizontal, margin)
            .padding(.top, metrics.pt(9))
            .padding(.bottom, metrics.pt(12))
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < -metrics.pt(13)
        } action: { _, pulledPastTop in
            if pulledPastTop {
                onClose()
            }
        }
        .overlay(alignment: .bottom) {
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
            .padding(.bottom, metrics.pt(1.5))
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
            recognitionIndicator()
            Button(action: onProfile) {
                ProfileAvatar(profile: session.activeProfile, diameter: metrics.pt(9.5))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(session.activeProfile.map { Text("Switch profile. Current: \($0.name)") } ?? Text("Switch profile. Current: Guest"))
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
            OpenSettingsButton()
                .font(.system(size: metrics.text(3.1), weight: .semibold))
                .buttonStyle(.glass)
        }
        .padding(metrics.pt(3.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubTile(metrics)
    }

    @ViewBuilder
    private func itemView(_ item: HomeScreenItem) -> some View {
        let visibility = VisibilityPolicy.visibility(for: item.access, context: audience)
        Group {
            switch item {
            case .app(let app):
                AppIconView(app: app, isRedacted: visibility == .redacted) { onOpen(app) }
            case .widget(let widget):
                HomeWidgetView(kind: widget, isRedacted: visibility == .redacted) { onOpen(widget.app) }
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

/// An app icon: a rounded square in the app's color with its symbol, and the name underneath.
struct AppIconView: View {
    let app: HubApp
    let isRedacted: Bool
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
                    if isRedacted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: size * 0.2, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(size * 0.07)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(width: size, height: size)
                .saturation(isRedacted ? 0 : 1)
                .opacity(isRedacted ? 0.5 : 1)
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
        .disabled(isRedacted)
        .hoverEffect(.lift)
        .accessibilityHint(isRedacted ? Text("Locked until the hub recognizes its owner.") : Text(verbatim: ""))
    }
}
