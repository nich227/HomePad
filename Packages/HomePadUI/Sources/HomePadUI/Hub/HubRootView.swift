import HomePadCore
import HomePadUICore
import SwiftUI
import UIKit

/// The hub: faces to rest on, the Home Screen one swipe up, and apps. Everything is drawn on a
/// square canvas centered on black; with the fill layout a second column uses the rest of the
/// screen.
public struct HubRootView: View {
    private let session: HouseholdSession
    private let settings: HomePadSettings
    private let slots: HubFeatureSlots
    private let environment: HubEnvironment
    private let navigator: HubNavigator
    private let facePosition: (@MainActor () -> FacePosition?)?
    private let ambientLight: (@MainActor () -> AmbientLightHint?)?
    private let onSummaryChange: (@MainActor (HubStatusSummary) -> Void)?

    @State private var model: HubModel
    @FocusState private var hasKeyboardFocus: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.calendar) private var calendar
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - facePosition: Where the viewer is in front of the screen, for the Flow face.
    ///   - ambientLight: How bright the room looks, for night mode's "follow room light".
    ///   - onSummaryChange: Called when what the hub shows changes, to forward to companions.
    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        slots: HubFeatureSlots = HubFeatureSlots(),
        environment: HubEnvironment,
        navigator: HubNavigator,
        facePosition: (@MainActor () -> FacePosition?)? = nil,
        ambientLight: (@MainActor () -> AmbientLightHint?)? = nil,
        onSummaryChange: (@MainActor (HubStatusSummary) -> Void)? = nil
    ) {
        self.session = session
        self.settings = settings
        self.slots = slots
        self.environment = environment
        self.navigator = navigator
        self.facePosition = facePosition
        self.ambientLight = ambientLight
        self.onSummaryChange = onSummaryChange
        _model = State(initialValue: HubModel(layoutStore: environment.layoutStore))
    }

    private var owner: LayoutOwner {
        session.activeProfile.map { .profile($0.id) } ?? .guest
    }

    public var body: some View {
        let preferences = HubPreferences(settings: settings)
        let audience = AudienceContext(
            isGuest: session.isGuest,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            setupMode: preferences.setupMode
        )
        let density = FaceDensity(proximity: session.proximity, adaptiveDetail: preferences.adaptiveDetail)
        GeometryReader { proxy in
            let layout = CanvasLayout(
                width: proxy.size.width,
                height: proxy.size.height,
                mode: preferences.canvas,
                gap: min(proxy.size.width, proxy.size.height) * 0.02
            )
            let metrics = HubMetrics(side: layout.square.width, textScale: dynamicTypeSize.hubTextScale)
            ZStack(alignment: .topLeading) {
                Color.black
                canvas(preferences: preferences, audience: audience, metrics: metrics)
                    .frame(width: layout.square.width, height: layout.square.height)
                    .clipShape(RoundedRectangle(cornerRadius: layout.square.width * CGFloat(CanvasLayout.cornerRadiusFraction), style: .continuous))
                    .offset(x: layout.square.x, y: layout.square.y)
                if let side = layout.side, model.night == .day {
                    SideColumn(isWide: side.width > side.height)
                        .frame(width: side.width, height: side.height)
                        .offset(x: side.x, y: side.y)
                        .transition(.opacity)
                }
                if navigator.state.isTakeoverPresented {
                    BeamTakeoverView(content: slots.beam) { navigator.dismissBeam() }
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(10)
                }
            }
            .environment(\.hubMetrics, metrics)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .environment(\.hubPreferences, preferences)
        .environment(\.hubUnits, HubUnits(preferences: preferences))
        .environment(\.faceDensity, density)
        .environment(\.hubAudience, audience)
        .environment(environment)
        .environment(session)
        .environment(navigator)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: navigator.state)
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: model.night)
        .animation(.smooth(duration: 0.3), value: model.showsSwitcher)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(.leftArrow) { keyStep(-1, preferences) }
        .onKeyPress(.rightArrow) { keyStep(1, preferences) }
        .onKeyPress(.upArrow) {
            guard navigator.state.surface == .faces else { return .ignored }
            navigator.showHomeScreen()
            return .handled
        }
        .onKeyPress(.escape) {
            model.showsSwitcher ? (model.showsSwitcher = false) : navigator.back()
            return .handled
        }
        .onAppear {
            hasKeyboardFocus = true
            model.adopt(owner: owner, enabledFaces: preferences.faces.enabledFaces)
            model.screen.setKeepAwake(preferences.keepAwake)
            environment.alarms.start(calendar: calendar)
            environment.music.start()
            environment.weather.configure(location: preferences.weatherLocation)
        }
        .onDisappear { model.screen.restore() }
        .onChange(of: owner) { _, newOwner in
            model.adopt(owner: newOwner, enabledFaces: preferences.faces.enabledFaces)
        }
        .onChange(of: audience) { _, newAudience in
            navigator.audienceChanged(newAudience)
        }
        .onChange(of: preferences) { _, updated in
            model.reconcileFace(enabledFaces: updated.faces.enabledFaces)
            model.screen.setKeepAwake(updated.keepAwake)
            environment.weather.configure(location: updated.weatherLocation)
        }
        .onChange(of: model.face) { _, face in
            if let face {
                model.rememberFace(face)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                model.screen.restore()
                return
            }
            settings.refresh()
            model.screen.setKeepAwake(HubPreferences(settings: settings).keepAwake)
            while !Task.isCancelled {
                housekeeping()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvas(preferences: HubPreferences, audience: AudienceContext, metrics: HubMetrics) -> some View {
        let surface = navigator.state.surface
        let onFaces = surface == .faces
        let blursFace = !onFaces && preferences.homeWallpaper == .face
        ZStack {
            FacePagerView(faces: preferences.faces.enabledFaces, selection: $model.face, facePosition: facePosition)
                .blur(radius: blursFace ? metrics.pt(5) : 0)
                .overlay(Color.black.opacity(onFaces ? 0 : (blursFace ? 0.28 : 1)))
                .allowsHitTesting(onFaces)
                .accessibilityHidden(!onFaces)
                .simultaneousGesture(swipe(up: { navigator.showHomeScreen() }))

            if onFaces {
                faceChrome(metrics: metrics)
                    .transition(.opacity)
            } else {
                HomeScreenView(
                    layout: model.layout,
                    profileCount: session.profiles.count,
                    recognitionIndicator: slots.recognitionIndicator,
                    onOpen: { open($0, audience: audience) },
                    onMove: { model.move(itemID: $0, onto: $1) },
                    onProfile: { model.showsSwitcher = true },
                    onClose: { navigator.showFaces() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if case .app(let app) = surface {
                AppHostView(app: app, slots: slots) { navigator.back() }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if case .night = model.night {
                NightClockView()
                    .transition(.opacity)
                    .zIndex(4)
            }

            alerts
                .zIndex(5)

            if session.profiles.isEmpty, preferences.setupMode, !model.helloDismissed, model.night == .day {
                HelloOverlay(
                    onAddPeople: {
                        model.helloDismissed = true
                        open(.people, audience: audience)
                    },
                    onDismiss: { model.helloDismissed = true }
                )
                .transition(.opacity)
                .zIndex(6)
            }

            if model.showsSwitcher {
                ProfileSwitcher(session: session, showsSetupHint: VisibilityPolicy.needsSetupHint(profileCount: session.profiles.count, setupMode: preferences.setupMode)) {
                    model.showsSwitcher = false
                }
                .transition(.opacity)
                .zIndex(7)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            model.touch()
            model.updateNight(schedule: preferences.night, ambient: ambientLight?(), now: Date(), calendar: calendar)
        })
    }

    /// What floats over a face: the profile chip, the timer strip, and a Home Screen button for
    /// people using a pointer or assistive technology.
    private func faceChrome(metrics: HubMetrics) -> some View {
        let detailed = FaceDensity(proximity: session.proximity, adaptiveDetail: HubPreferences(settings: settings).adaptiveDetail) == .detailed
        return VStack(spacing: 0) {
            HStack(spacing: metrics.pt(1.5)) {
                Spacer()
                slots.recognitionIndicator()
                ProfileChip(profile: session.activeProfile, isSomeonePresent: session.isSomeonePresent) {
                    model.showsSwitcher = true
                }
            }
            .opacity(detailed ? 1 : 0.55)
            Spacer()
            TimerStripView(strip: environment.timers.strip) { open(.timers, audience: nil) }
            if detailed {
                Button {
                    navigator.showHomeScreen()
                } label: {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: metrics.pt(5), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: metrics.pt(16), height: metrics.pt(5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Show Home Screen")
                .transition(.opacity)
            }
        }
        .padding(metrics.pt(3.5))
    }

    @ViewBuilder
    private var alerts: some View {
        if !environment.timers.ringing.isEmpty {
            TimerDoneOverlay(timers: environment.timers.ringing) { environment.timers.dismissRinging() }
                .transition(.opacity)
        } else if let alarm = environment.alarms.ringing {
            AlarmRingingOverlay(alarm: alarm, onSnooze: { environment.alarms.snooze() }, onStop: { environment.alarms.stopRinging() })
                .transition(.opacity)
        }
    }

    // MARK: Actions

    private func open(_ app: HubApp, audience: AudienceContext?) {
        if app == .settings {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            return
        }
        let context = audience ?? AudienceContext(
            isGuest: session.isGuest,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            setupMode: settings[GeneralSettings.setupMode]
        )
        navigator.open(app, context: context)
    }

    private func keyStep(_ step: Int, _ preferences: HubPreferences) -> KeyPress.Result {
        guard navigator.state.surface == .faces else { return .ignored }
        model.touch()
        withAnimation(reduceMotion ? nil : .smooth) {
            model.step(step, enabledFaces: preferences.faces.enabledFaces)
        }
        return .handled
    }

    private func swipe(up: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            model.touch()
            if SwipeDecision.vertical(translationX: value.translation.width, translationY: value.translation.height) == .up {
                up()
            }
        }
    }

    /// Runs every few seconds while the hub is in front: night mode, drifting back to the face,
    /// and telling companions what is showing.
    private func housekeeping() {
        let now = Date()
        let preferences = HubPreferences(settings: settings)
        model.updateNight(schedule: preferences.night, ambient: ambientLight?(), now: now, calendar: calendar)
        navigator.restIfIdle(isSomeonePresent: session.isSomeonePresent, idleSeconds: now.timeIntervalSince(model.lastInteraction))
        guard let onSummaryChange, let face = model.face else { return }
        var night = false
        if case .night = model.night { night = true }
        let summary = HubStatusSummary(
            surface: navigator.state.surface,
            face: face,
            profileName: session.activeProfile?.name,
            timers: environment.timers.engine.timers,
            nowPlaying: environment.music.nowPlaying,
            isNight: night,
            at: now
        )
        if let changed = model.summaryIfChanged(summary) {
            onSummaryChange(changed)
        }
    }
}

/// The faces side by side. Swiping left or right moves between them.
struct FacePagerView: View {
    let faces: [FaceKind]
    @Binding var selection: FaceKind?
    let facePosition: (@MainActor () -> FacePosition?)?
    @Environment(\.hubMetrics) private var metrics

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(faces) { kind in
                    FaceView(kind: kind, facePosition: facePosition)
                        .frame(width: metrics.side, height: metrics.side)
                        .clipped()
                        .id(kind)
                        .accessibilityLabel(kind.title)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        .accessibilityHint("Swipe left or right to change the face. Swipe up for the Home Screen.")
    }
}

#Preview("Hub, square") {
    HubPreviewHost(canvas: "square")
}

#Preview("Hub, fill") {
    HubPreviewHost(canvas: "fill")
}

/// A hub wired to sample services, for previews.
struct HubPreviewHost: View {
    @State private var session: HouseholdSession
    @State private var settings: HomePadSettings
    @State private var environment = HubEnvironment.preview()
    @State private var navigator = HubNavigator()

    init(canvas: String) {
        let session = HouseholdSession(store: InMemoryProfileStore(profiles: [
            HouseholdProfile(name: "Erica", tint: .purple),
            HouseholdProfile(name: "Danny", tint: .blue),
        ]))
        if let profile = session.profiles.first {
            session.faceRecognized(profileID: profile.id, proximity: .near)
        }
        _session = State(initialValue: session)
        let defaults = UserDefaults(suiteName: "HomePadUI.preview.\(canvas)") ?? .standard
        // Registered, not written: the app never stores a preference, even in a preview.
        defaults.register(defaults: [UISettings.Display.canvas.name: canvas])
        _settings = State(initialValue: HomePadSettings(defaults: defaults))
    }

    var body: some View {
        HubRootView(session: session, settings: settings, environment: environment, navigator: navigator)
    }
}
