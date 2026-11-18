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
    private let onWelcomeFinished: (@MainActor () -> Void)?
    private let hooks = HubTestHooks.current

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
    ///   - onWelcomeFinished: Called once, when the first-run welcome is out of the way or was
    ///     never needed. Start anything that makes the system ask for permission here, such as
    ///     the camera, so the prompt does not land on the welcome.
    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        slots: HubFeatureSlots = HubFeatureSlots(),
        environment: HubEnvironment,
        navigator: HubNavigator,
        facePosition: (@MainActor () -> FacePosition?)? = nil,
        ambientLight: (@MainActor () -> AmbientLightHint?)? = nil,
        onSummaryChange: (@MainActor (HubStatusSummary) -> Void)? = nil,
        onWelcomeFinished: (@MainActor () -> Void)? = nil
    ) {
        self.session = session
        self.settings = settings
        self.slots = slots
        self.environment = environment
        self.navigator = navigator
        self.facePosition = facePosition
        self.ambientLight = ambientLight
        self.onSummaryChange = onSummaryChange
        self.onWelcomeFinished = onWelcomeFinished
        _model = State(initialValue: HubModel(layoutStore: environment.layoutStore))
    }

    private var owner: LayoutOwner {
        session.activeProfile.map { .profile($0.id) } ?? .guest
    }

    /// Preferences as set in Settings. A UI test may force the canvas layout for one launch.
    private var currentPreferences: HubPreferences {
        var preferences = HubPreferences(settings: settings)
        if let canvas = hooks.canvas {
            preferences.canvas = canvas
        }
        return preferences
    }

    /// The first-run welcome is due: nobody is enrolled, people can be added from here, and it
    /// has not been dismissed in this launch.
    private func needsWelcome(_ preferences: HubPreferences) -> Bool {
        session.profiles.isEmpty && preferences.setupMode && !model.helloDismissed && !hooks.skipsWelcome
    }

    public var body: some View {
        let preferences = currentPreferences
        let needsWelcome = needsWelcome(preferences)
        let audience = AudienceContext(
            isGuest: session.isGuest,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            setupMode: preferences.setupMode
        )
        let density = FaceDensity(proximity: session.proximity, adaptiveDetail: preferences.adaptiveDetail)
        let showsDeviceUnlock = VisibilityPolicy.showsDeviceUnlock(context: audience, isDeviceUnlockOffered: isDeviceUnlockOffered)
        GeometryReader { proxy in
            HubPanes(simulatesFold: hooks.foldsHub) {
                chromePane(container: proxy.size, preferences: preferences, isHidden: needsWelcome || model.night != .day)
            } canvas: {
                canvasPane(container: proxy.size, preferences: preferences, audience: audience)
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .environment(\.hubPreferences, preferences)
        .environment(\.hubUnits, HubUnits(preferences: preferences))
        .environment(\.faceDensity, density)
        .environment(\.hubAudience, audience)
        .environment(\.hubMayPrompt, !needsWelcome)
        .environment(\.hubMayRunScenes, HomeControlPolicy.mayRunScenes(activation: session.activation, profiles: session.profiles))
        .environment(\.hubShowsDeviceUnlock, showsDeviceUnlock)
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
            applyTestHooks()
            model.adopt(owner: owner, enabledFaces: preferences.faces.enabledFaces)
            model.screen.setKeepAwake(preferences.keepAwake)
            environment.alarms.start(calendar: calendar)
            environment.weather.configure(location: preferences.weatherLocation)
        }
        .onChange(of: needsWelcome, initial: true) { _, needed in
            if !needed, model.markWelcomeFinished() {
                onWelcomeFinished?()
            }
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
            model.screen.setKeepAwake(currentPreferences.keepAwake)
            while !Task.isCancelled {
                housekeeping()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Panes

    private func placement(of pane: CGSize, in container: CGSize) -> HubPanePlacement {
        HubPanePolicy.placement(
            containerWidth: Double(container.width),
            containerHeight: Double(container.height),
            paneWidth: Double(pane.width),
            paneHeight: Double(pane.height)
        )
    }

    private func canvasLayout(in size: CGSize, mode: CanvasMode) -> CanvasLayout {
        CanvasLayout(width: size.width, height: size.height, mode: mode, gap: min(size.width, size.height) * 0.02)
    }

    /// The square canvas. With the display flat it sits where `CanvasLayout` puts it, with room
    /// around it for the other pane. On one side of a fold it is the largest square that fits.
    private func canvasPane(container: CGSize, preferences: HubPreferences, audience: AudienceContext) -> some View {
        GeometryReader { pane in
            let isApart = placement(of: pane.size, in: container) == .apart
            let layout = canvasLayout(in: pane.size, mode: isApart ? .square : preferences.canvas)
            let metrics = HubMetrics(side: layout.square.width, textScale: dynamicTypeSize.hubTextScale)
            ZStack(alignment: .topLeading) {
                Color.black
                canvas(preferences: preferences, audience: audience, metrics: metrics, hasBezelStatus: isApart || layout.status != nil)
                    .frame(width: layout.square.width, height: layout.square.height)
                    .clipShape(RoundedRectangle(cornerRadius: layout.square.width * CGFloat(CanvasLayout.cornerRadiusFraction), style: .continuous))
                    .offset(x: layout.square.x, y: layout.square.y)
                if navigator.state.isTakeoverPresented {
                    BeamTakeoverView(content: slots.beam) { navigator.dismissBeam() }
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(10)
                }
            }
            .environment(\.hubMetrics, metrics)
            .environment(\.hubChromeIsApart, isApart)
        }
    }

    /// Everything around the canvas: who is in front, the way between the face and the Home
    /// Screen, and the widgets. With the display flat it is drawn in the space `CanvasLayout`
    /// leaves around the canvas and is clear everywhere else. On one side of a fold it fills its
    /// side: the status across the top, then running timers, then the widgets.
    @ViewBuilder
    private func chromePane(container: CGSize, preferences: HubPreferences, isHidden: Bool) -> some View {
        GeometryReader { pane in
            if isHidden {
                EmptyView()
            } else if placement(of: pane.size, in: container) == .apart {
                let panel = ChromePanelLayout(width: Double(pane.size.width), height: Double(pane.size.height))
                VStack(spacing: 0) {
                    status(clearance: clearance(for: panel.status, in: pane))
                        .frame(height: panel.status.height)
                    TimerStripView(strip: environment.timers.strip) { open(.timers, audience: nil) }
                    SideColumn(showsTimers: false)
                }
                .environment(\.hubMetrics, HubMetrics(side: panel.unitSide, textScale: dynamicTypeSize.hubTextScale))
                .transition(.opacity)
            } else if !navigator.state.isTakeoverPresented {
                let layout = canvasLayout(in: pane.size, mode: preferences.canvas)
                ZStack(alignment: .topLeading) {
                    if let side = layout.side {
                        SideColumn()
                            .frame(width: side.width, height: side.height)
                            .offset(x: side.x, y: side.y)
                    }
                    if let frame = layout.status {
                        status(clearance: clearance(for: frame, in: pane))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.x, y: frame.y)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.hubMetrics, HubMetrics(side: layout.square.width, textScale: dynamicTypeSize.hubTextScale))
                .transition(.opacity)
            }
        }
    }

    private func status(clearance: EdgeInsets) -> some View {
        BezelStatusView(
            profile: session.activeProfile,
            isSomeonePresent: session.isSomeonePresent,
            isOnFaces: navigator.state.surface == .faces,
            showsAvatar: navigator.state.surface != .homeScreen,
            indicator: slots.recognitionIndicator,
            onProfile: { model.showsSwitcher = true },
            onToggleSurface: {
                model.touch()
                navigator.state.surface == .faces ? navigator.showHomeScreen() : navigator.showFaces()
            },
            onUnlock: { runDeviceUnlock(thenOpen: nil) },
            clearance: clearance
        )
    }

    /// How far the status must stay in from the edges of its frame to keep clear of the safe
    /// area and of anything that covers the display, such as a camera.
    private func clearance(for frame: CanvasFrame, in pane: GeometryProxy) -> EdgeInsets {
        let safe = pane.safeAreaInsets
        var obstacles = CanvasFrame.edges(
            of: CanvasInsets(top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing),
            width: Double(pane.size.width),
            height: Double(pane.size.height)
        )
        if #available(iOS 27.1, *) {
            obstacles += pane.reservedRegions(kind: .occlusion).map {
                CanvasFrame(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
            }
        }
        let insets = frame.insets(clearing: obstacles)
        return EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvas(preferences: HubPreferences, audience: AudienceContext, metrics: HubMetrics, hasBezelStatus: Bool) -> some View {
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
                faceChrome(metrics: metrics, showsHomeButton: !hasBezelStatus)
                    .transition(.opacity)
            } else {
                HomeScreenView(
                    layout: model.layout,
                    profileCount: session.profiles.count,
                    recognitionIndicator: hasBezelStatus ? nil : slots.recognitionIndicator,
                    onOpen: { open($0, audience: audience) },
                    onUnlock: { runDeviceUnlock(thenOpen: $0) },
                    showsFaceButton: !hasBezelStatus,
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

            if needsWelcome(preferences), model.night == .day {
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
                ProfileSwitcher(
                    session: session,
                    showsSetupHint: VisibilityPolicy.needsSetupHint(profileCount: session.profiles.count, setupMode: preferences.setupMode),
                    onUnlock: { runDeviceUnlock(thenOpen: nil) },
                    onClose: { model.showsSwitcher = false }
                )
                .transition(.opacity)
                .zIndex(7)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            model.touch()
            model.updateNight(schedule: preferences.night, ambient: ambientLight?(), now: Date(), calendar: calendar, forced: hooks.forcesNight)
        })
    }

    /// What floats over a face: the timer strip, and, only when there is no room beside the
    /// canvas for it, a Home Screen button for people using a pointer or assistive technology.
    private func faceChrome(metrics: HubMetrics, showsHomeButton: Bool) -> some View {
        FaceChrome(showsHomeButton: showsHomeButton, onTimers: { open(.timers, audience: nil) }, onHome: { navigator.showHomeScreen() })
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

    /// Whether the device's own biometrics can confirm the member the camera matched.
    private var isDeviceUnlockOffered: Bool {
        // A UI test stands in for the biometric hardware, which the simulator does not have.
        if hooks.offersDeviceUnlock {
            return session.canConfirmWithDeviceBiometrics
        }
        return slots.deviceUnlock?.isOffered() ?? false
    }

    /// Runs the device's biometrics. When that unlocks personal content, opens the app the
    /// person tapped, if there was one.
    private func runDeviceUnlock(thenOpen app: HubApp?) {
        Task {
            let succeeded: Bool
            if hooks.offersDeviceUnlock {
                succeeded = session.confirmWithDeviceBiometrics()
            } else if let deviceUnlock = slots.deviceUnlock {
                succeeded = await deviceUnlock.unlock()
            } else {
                succeeded = false
            }
            let context = AudienceContext(
                isGuest: session.isGuest,
                isPersonalContentUnlocked: session.isPersonalContentUnlocked,
                setupMode: currentPreferences.setupMode
            )
            if let app = VisibilityPolicy.appToOpen(afterUnlock: succeeded, requested: app, context: context) {
                navigator.open(app, context: context)
            }
        }
    }

    /// Puts the hub in the state a UI test asked for. Does nothing unless a test set a hook.
    private func applyTestHooks() {
        guard let audience = hooks.audience ?? (hooks.proximity == nil ? nil : .guest) else { return }
        let proximity = hooks.proximity ?? .near
        session.unknownFacePresent(proximity: proximity)
        guard let profile = session.profiles.first else { return }
        switch audience {
        case .guest:
            break
        case .manual:
            try? session.switchManually(to: profile.id)
        case .recognized:
            session.faceRecognized(profileID: profile.id, proximity: proximity)
        }
        if hooks.offersDeviceUnlock {
            session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: proximity)
        }
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
        let preferences = currentPreferences
        model.updateNight(schedule: preferences.night, ambient: ambientLight?(), now: now, calendar: calendar, forced: hooks.forcesNight)
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

/// What floats over a face: the timer strip, and, only when there is no room beside the canvas
/// for it, a Home Screen button for people using a pointer or assistive technology. When a fold
/// gives the status its own side, the timers are shown there and not on the face.
private struct FaceChrome: View {
    let showsHomeButton: Bool
    let onTimers: () -> Void
    let onHome: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubChromeIsApart) private var chromeIsApart
    @Environment(HubEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if !chromeIsApart {
                TimerStripView(strip: environment.timers.strip, action: onTimers)
            }
            if showsHomeButton {
                Button(action: onHome) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: metrics.pt(5), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: metrics.pt(16), height: metrics.pt(5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel("Show Home Screen")
                .accessibilityIdentifier("hub.showHomeScreen")
            }
        }
        .padding(metrics.pt(3.5))
    }
}

/// Holds the hub's two panes. With the display flat the chrome lies over the canvas, each
/// drawing in its own part of the screen. When the display is partly folded the system gives
/// each pane one side of the fold, so nothing sits in it.
private struct HubPanes<Chrome: View, Canvas: View>: View {
    let simulatesFold: Bool
    @ViewBuilder let chrome: Chrome
    @ViewBuilder let canvas: Canvas

    var body: some View {
        if simulatesFold {
            // Only for UI tests: halves with a gap between them, in the order the system uses
            // for a folded overlay arrangement.
            GeometryReader { proxy in
                let isWide = proxy.size.width > proxy.size.height
                let layout = isWide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                layout {
                    canvas
                    chrome
                }
            }
        } else if #available(iOS 27.1, *) {
            ArrangementView {
                chrome
            } secondary: {
                canvas
            }
            .arrangementViewStyle(.overlay)
        } else {
            ZStack {
                canvas
                chrome
            }
        }
    }
}

/// The faces side by side. Swiping left or right moves between them.
struct FacePagerView: View {
    let faces: [FaceKind]
    @Binding var selection: FaceKind?
    let facePosition: (@MainActor () -> FacePosition?)?
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMayPrompt) private var mayPrompt

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(faces) { kind in
                    FaceView(kind: kind, facePosition: facePosition)
                        .frame(width: metrics.side, height: metrics.side)
                        .clipped()
                        .id(kind)
                        // Neighboring faces are built ahead of time. Only the one in front may
                        // start a service that asks for permission.
                        .environment(\.hubMayPrompt, mayPrompt && selection == kind)
                        .accessibilityLabel(kind.title)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("hub.faces")
        .accessibilityHint("Swipe left or right to change the face. Swipe up for the Home Screen.")
        .overlay(alignment: .topLeading) {
            // Says which face is in front, for assistive technology and for UI tests.
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Current face")
                .accessibilityValue(selection.map { Text($0.title) } ?? Text(verbatim: ""))
                .accessibilityIdentifier("hub.currentFace")
        }
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
