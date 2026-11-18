import HomePadCore
import HomePadUICore
import SwiftUI

/// The Home Screen: a greeting, a row of the person's widgets, and a grid of app icons that
/// scrolls up and down, over the blurred face. The grid has four columns, and more where the
/// screen is wide enough.
struct HomeScreenView: View {
    let layout: HomeScreenLayout
    let profileCount: Int
    /// Optional apps that another package is supplying right now.
    let availableApps: Set<HubApp>
    /// The app, and where its icon is on the canvas, so the app can grow out of it.
    let onOpen: (HubApp, UnitPoint) -> Void
    /// Runs the device's biometrics, then opens the app if that unlocked it.
    let onUnlock: (HubApp) -> Void
    let onMove: (String, String) -> Void
    let onClose: () -> Void

    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubPreferences) private var preferences
    @Environment(\.hubAudience) private var audience
    @Environment(\.hubShowsDeviceUnlock) private var showsDeviceUnlock
    @Environment(\.calendar) private var calendar
    @Environment(HouseholdSession.self) private var session
    /// How far down the grid is scrolled, 0...1, or nil when everything fits.
    @State private var scrollFraction: Double?

    private var visibleItems: [HomeScreenItem] {
        layout.items.filter { item in
            if case .app(let app) = item, !VisibilityPolicy.isListed(app, available: availableApps) { return false }
            return VisibilityPolicy.visibility(for: item.access, context: audience) != .hidden
        }
    }

    var body: some View {
        let unit = Double(metrics.side) / 100
        let margin = metrics.pt(CGFloat(HomeScreenGrid.margin))
        let gap = metrics.pt(CGFloat(HomeScreenGrid.gap))
        let columns = HomeScreenGrid.columns(width: Double(metrics.width), unit: unit)
        let widgetCount = HomeScreenGrid.widgetCount(width: Double(metrics.width), unit: unit)
        let items = visibleItems
        let widgets = preferences.homeShowsWidgets ? Array(items.filter { if case .widget = $0 { true } else { false } }.prefix(widgetCount)) : []
        let apps = items.filter { if case .app = $0 { true } else { false } }
        let widgetSide = (metrics.width - margin * 2 - gap * CGFloat(max(widgets.count, widgetCount) - 1)) / CGFloat(max(widgets.count, widgetCount))
        let fade = metrics.token(28)
        // At the top the grid is gone before it reaches the pill and the status.
        let topFade = metrics.topBar
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: metrics.pt(4)) {
                header
                if VisibilityPolicy.needsSetupHint(profileCount: profileCount, setupMode: preferences.setupMode) {
                    setupNote
                }
                if !widgets.isEmpty {
                    GlassEffectContainer(spacing: gap) {
                        HStack(spacing: gap) {
                            ForEach(widgets) { item in
                                itemView(item, widgetSide: widgetSide)
                            }
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: columns), spacing: metrics.pt(3)) {
                    ForEach(apps) { item in
                        itemView(item, widgetSide: widgetSide)
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, metrics.topBar + metrics.pt(1))
            .padding(.bottom, metrics.bottomBar + metrics.pt(8))
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("hub.homeScreen")
        // The grid fades out toward the top and bottom edges instead of being cut off.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: topFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
            }
        }
        .onScrollGeometryChange(for: Double?.self) { geometry in
            let range = geometry.contentSize.height - geometry.containerSize.height
            guard range > 1 else { return nil }
            return min(max((geometry.contentOffset.y + geometry.contentInsets.top) / range, 0), 1)
        } action: { _, fraction in
            scrollFraction = fraction
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < -metrics.pt(13)
        } action: { _, pulledPastTop in
            if pulledPastTop {
                onClose()
            }
        }
        .overlay(alignment: .trailing) {
            if let scrollFraction {
                pageIndicator(scrollFraction)
            }
        }
    }

    /// A short track on the trailing edge with a thumb that follows the scroll.
    private func pageIndicator(_ fraction: Double) -> some View {
        let height = metrics.token(72)
        let thumb = metrics.token(26)
        return Capsule()
            .fill(.white.opacity(0.22))
            .frame(width: max(metrics.token(5), 4), height: height)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(height: thumb)
                    .offset(y: (height - thumb) * CGFloat(fraction))
            }
            .padding(.trailing, metrics.token(6))
            .accessibilityHidden(true)
    }

    private var header: some View {
        let hour = calendar.component(.hour, from: Date())
        return VStack(alignment: .leading, spacing: metrics.pt(0.4)) {
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
    private func itemView(_ item: HomeScreenItem, widgetSide: CGFloat) -> some View {
        let visibility = VisibilityPolicy.visibility(for: item.access, context: audience)
        let tap = VisibilityPolicy.tapAction(for: item.access, context: audience, isDeviceUnlockOffered: showsDeviceUnlock)
        let act: (HubApp, UnitPoint) -> Void = { app, anchor in
            switch tap {
            case .open: onOpen(app, anchor)
            case .requestUnlock: onUnlock(app)
            case .none: break
            }
        }
        Group {
            switch item {
            case .app(let app):
                AppIconView(app: app, isRedacted: visibility == .redacted, offersUnlock: tap == .requestUnlock) { act(app, $0) }
            case .widget(let widget):
                // A widget is laid out in hundredths of a canvas on which it is 39.4 across, so
                // it is given the canvas that makes it the size of its place in the row.
                HomeWidgetView(kind: widget, isRedacted: visibility == .redacted, offersUnlock: tap == .requestUnlock) { act(widget.app, .center) }
                    .frame(width: widgetSide, height: widgetSide)
                    .environment(\.hubMetrics, HubMetrics(side: widgetSide / 0.394, textScale: metrics.textScale))
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

/// An app icon: a rounded square in the app's color with its symbol, and the name underneath.
/// In Night Mode it is an outline, so the only color on screen stays red.
struct AppIconView: View {
    let app: HubApp
    let isRedacted: Bool
    /// The icon is locked, and tapping it asks for the device's biometrics.
    var offersUnlock = false
    /// Called with where the icon is on the canvas.
    let action: (UnitPoint) -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubIsNight) private var isNight
    @State private var center = CGPoint.zero

    var body: some View {
        let size = max(metrics.token(DesignTokens.appIcon), 56)
        let shape = RoundedRectangle(cornerRadius: size * 17 / 76, style: .continuous)
        let base = app.tint.map { Color($0) } ?? Color(white: 0.34)
        Button {
            action(UnitPoint(x: center.x / max(metrics.width, 1), y: center.y / max(metrics.height, 1)))
        } label: {
            VStack(spacing: metrics.token(6)) {
                ZStack {
                    if isNight {
                        shape.stroke(.white, lineWidth: 2)
                    } else {
                        shape
                            .fill(LinearGradient(colors: [base.opacity(0.92), base], startPoint: .top, endPoint: .bottom))
                            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)))
                    }
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
                    .font(.system(size: metrics.textToken(13), weight: .medium))
                    .foregroundStyle(.white.opacity(isRedacted ? 0.5 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .shadow(color: .black.opacity(0.35), radius: metrics.pt(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRedacted && !offersUnlock)
        .hoverEffect(.lift)
        .onGeometryChange(for: CGPoint.self) { proxy in
            let frame = proxy.frame(in: .named(HubCoordinateSpace.canvas))
            return CGPoint(x: frame.midX, y: frame.midY)
        } action: { center = $0 }
        .accessibilityHint(lockedHint)
        .accessibilityIdentifier("app.\(app.rawValue)")
    }
}

/// Names of the coordinate spaces the shell measures in.
enum HubCoordinateSpace {
    static let canvas = "hubCanvas"
}
