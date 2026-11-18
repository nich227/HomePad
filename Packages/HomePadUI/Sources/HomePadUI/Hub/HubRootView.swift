import HomePadCore
import HomePadUICore
import SwiftUI
import UIKit

/// The hub: faces to rest on, the Home Screen one swipe up, and apps, filling whatever shape the
/// display is. The live pill, the status, and the bar to the Home Screen float over the face;
/// the control center, the face picker, and controls opened from a tile float over everything.
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
    ///   - facePosition: Where the viewer is in front of the screen, for the Flow face and the
    ///     wallpaper's parallax.
    ///   - ambientLight: How bright the room looks, for Night Mode's "follow room light".
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

    private var currentAudience: AudienceContext {
        AudienceContext(
            isGuest: session.isGuest,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            setupMode: settings[GeneralSettings.setupMode]
        )
    }

    /// The first-run welcome is due: nobody is enrolled, people can be added from here, and it
    /// has not been dismissed in this launch.
    private func needsWelcome(_ preferences: HubPreferences) -> Bool {
        session.profiles.isEmpty && preferences.setupMode && !model.helloDismissed && !hooks.skipsWelcome
    }

    /// The assistant another package supplies. A UI test may ask for a stand-in when there is
    /// none.
    private var assistant: HubAssistant? {
        slots.assistant ?? (hooks.showsSampleAssistant ? SampleAssistant.slot : nil)
    }

    private var isAssistantAvailable: Bool {
        assistant?.isAvailable() ?? false
    }

    public var body: some View {
        let preferences = currentPreferences
        let needsWelcome = needsWelcome(preferences)
        let audience = currentAudience
        let density = FaceDensity(proximity: session.proximity, adaptiveDetail: preferences.adaptiveDetail)
        let showsDeviceUnlock = VisibilityPolicy.showsDeviceUnlock(context: audience, isDeviceUnlockOffered: isDeviceUnlockOffered)
        let motion = HubMotion(reducesMotion: reduceMotion, slowdown: hooks.slowMotion ?? 1)
        GeometryReader { proxy in
            HubPanes(simulatesFold: hooks.foldsHub) {
                chromePane(container: proxy.size, isHidden: needsWelcome)
            } canvas: {
                canvasPane(container: proxy.size, preferences: preferences, audience: audience)
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        // Night Mode is applied here and nowhere else, so nothing drawn by the hub, or by a
        // package it hosts, is left in color.
        .hubNightTint(model.night.isNight)
        .environment(\.hubPreferences, preferences)
        .environment(\.hubUnits, HubUnits(preferences: preferences))
        .environment(\.faceDensity, density)
        .environment(\.hubAudience, audience)
        .environment(\.hubMayPrompt, !needsWelcome)
        .environment(\.hubMayRunScenes, HomeControlPolicy.mayRunScenes(activation: session.activation, profiles: session.profiles))
        .environment(\.hubShowsDeviceUnlock, showsDeviceUnlock)
        .environment(\.hubSolidGlass, hooks.usesSolidGlass)
        .environment(\.hubMotion, motion)
        .environment(\.hubViewerPosition, facePosition)
        .environment(\.hubSend) { send($0) }
        .environment(environment)
        .environment(session)
        .environment(navigator)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // The hub has its own swipes from the top and bottom edges. The system's take a second
        // swipe, so the first one always reaches the hub.
        .defersSystemGestures(on: .all)
        .animation(motion.spring, value: navigator.state)
        .animation(motion.gentle, value: model.night)
        .animation(motion.gentle, value: density)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(.leftArrow) { keyStep(-1, preferences) }
        .onKeyPress(.rightArrow) { keyStep(1, preferences) }
        .onKeyPress(.upArrow) {
            guard navigator.state.surface == .faces else { return .ignored }
            send(.swipeUpFromBottomEdge)
            return .handled
        }
        .onKeyPress(.escape) {
            model.isPillExpanded ? (model.isPillExpanded = false) : navigator.back()
            return .handled
        }
        .onAppear {
            hasKeyboardFocus = true
            applyTestHooks()
            model.adopt(owner: owner, enabledFaces: preferences.faces.enabledFaces)
            model.screen.setKeepAwake(preferences.keepAwake)
            environment.alarms.start(calendar: calendar)
            environment.weather.configure(source: preferences.weatherSource, custom: preferences.weatherLocation)
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
        .onChange(of: session.activation.profileID) { previous, current in
            navigator.personChanged(from: previous, to: current)
        }
        .onChange(of: session.activation) { old, new in
            // The camera just recognized a member: say so in the pill for a moment.
            guard case .face(let id, _) = new, let profile = session.activeProfile else { return }
            if case .face(let before, _) = old, before == id { return }
            model.confirmRecognition(of: profile.name)
        }
        .onChange(of: preferences) { _, updated in
            model.reconcileFace(enabledFaces: updated.faces.enabledFaces)
            model.screen.setKeepAwake(updated.keepAwake)
            environment.weather.configure(source: updated.weatherSource, custom: updated.weatherLocation)
        }
        .onChange(of: model.face) { _, face in
            if let face {
                model.rememberFace(face)
            }
            navigator.facesChanged(enabled: currentPreferences.faces.enabledFaces, current: face)
        }
        .onChange(of: preferences.faces.enabledFaces, initial: true) { _, enabled in
            navigator.facesChanged(enabled: enabled, current: model.face)
        }
        .onChange(of: model.night.isNight, initial: true) { _, isNight in
            navigator.nightChanged(isNight)
        }
        // Requests from outside the shell, such as the assistant's actions.
        .onChange(of: navigator.nightRequest, initial: true) { _, request in
            guard let request else { return }
            model.setNight(request.isOn, schedule: currentPreferences.night, ambient: ambientLight?(), now: Date(), calendar: calendar, forced: hooks.forcesNight)
        }
        .onChange(of: navigator.faceRequest, initial: true) { _, request in
            guard let request else { return }
            model.touch()
            withAnimation(motion.spring) {
                model.face = request.kind
            }
        }
        .onChange(of: navigator.state.surface) { _, _ in
            model.isPillExpanded = false
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                // Leaving the foreground puts the screen back the way the person had it.
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

    /// The canvas: the whole pane, or with the Square setting the largest square that fits it.
    /// On one side of a fold it always fills its side.
    private func canvasPane(container: CGSize, preferences: HubPreferences, audience: AudienceContext) -> some View {
        GeometryReader { pane in
            let isApart = placement(of: pane.size, in: container) == .apart
            let layout = CanvasLayout(width: Double(pane.size.width), height: Double(pane.size.height), mode: isApart ? .fill : preferences.canvas)
            let size = CGSize(width: layout.canvas.width, height: layout.canvas.height)
            let metrics = HubMetrics(size: size, textScale: dynamicTypeSize.hubTextScale, topObstruction: topObstruction(over: layout.canvas, in: pane))
            ZStack(alignment: .topLeading) {
                Color.black
                canvas(preferences: preferences, audience: audience, metrics: metrics, isApart: isApart)
                    .frame(width: size.width, height: size.height)
                    .coordinateSpace(.named(HubCoordinateSpace.canvas))
                    .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                    .offset(x: layout.canvas.x, y: layout.canvas.y)
                if navigator.state.isTakeoverPresented {
                    BeamTakeoverView(content: slots.beam) { navigator.dismissBeam() }
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(10)
                }
                if navigator.state.overlay == .assistant, let assistant {
                    // The assistant draws its own edge and card. The hub gives it the screen.
                    assistant.overlay { navigator.dismissOverlay() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) {
                            // Says the assistant is open, for UI tests.
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityElement()
                                .accessibilityLabel("Assistant is open")
                                .accessibilityIdentifier("hub.assistantOpen")
                        }
                        .transition(.opacity)
                        .zIndex(11)
                }
            }
            .environment(\.hubMetrics, metrics)
            .environment(\.hubChromeIsApart, isApart)
            .simultaneousGesture(edgeSwipe(in: pane.size))
        }
    }

    /// How far down the top of the canvas is covered by the safe area or by something on the
    /// display, such as a camera.
    private func topObstruction(over canvas: CanvasFrame, in pane: GeometryProxy) -> CGFloat {
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
        return CGFloat(canvas.insets(clearing: obstacles).top)
    }

    /// With the display flat there is nothing beside the canvas, and this pane is empty. On one
    /// side of a fold it holds the status across the top, then running timers, then widgets.
    @ViewBuilder
    private func chromePane(container: CGSize, isHidden: Bool) -> some View {
        GeometryReader { pane in
            if !isHidden, placement(of: pane.size, in: container) == .apart {
                let panel = ChromePanelLayout(width: Double(pane.size.width), height: Double(pane.size.height))
                VStack(spacing: 0) {
                    BezelStatusView(
                        profile: session.activeProfile,
                        isSomeonePresent: session.isSomeonePresent,
                        isOnFaces: navigator.state.surface == .faces,
                        showsAvatar: true,
                        indicator: slots.recognitionIndicator,
                        onProfile: { send(.swipeDownFromTopTrailing) },
                        onToggleSurface: {
                            model.touch()
                            navigator.state.surface == .faces ? navigator.showHomeScreen() : navigator.showFaces()
                        },
                        onUnlock: { runDeviceUnlock(thenOpen: nil) }
                    )
                    .frame(height: panel.status.height)
                    TimerStripView(strip: environment.timers.strip) { open(.timers) }
                    SideColumn(showsTimers: false)
                }
                .environment(\.hubMetrics, HubMetrics(side: panel.unitSide, textScale: dynamicTypeSize.hubTextScale))
                .transition(.opacity)
            }
        }
    }

    // MARK: Canvas

    @ViewBuilder
    private func canvas(preferences: HubPreferences, audience: AudienceContext, metrics: HubMetrics, isApart: Bool) -> some View {
        let state = navigator.state
        let surface = state.surface
        let onFaces = surface == .faces
        let isNight = model.night.isNight
        let blursFace = !onFaces && preferences.homeWallpaper == .face && !isNight
        let needsWelcome = needsWelcome(preferences)
        ZStack {
            FacePagerView(faces: preferences.faces.enabledFaces, selection: $model.face, facePosition: facePosition)
                .scaleEffect(onFaces ? 1 : 1.05)
                .blur(radius: blursFace ? metrics.token(28) : 0)
                .overlay(Color.black.opacity(onFaces ? 0 : (blursFace ? 0.3 : 1)))
                .allowsHitTesting(state.canChangeFace)
                .accessibilityHidden(!onFaces)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in send(.longPressCanvas) })
                .accessibilityAction(named: "Choose Face") { send(.longPressCanvas) }

            if !onFaces {
                HomeScreenView(
                    layout: model.layout,
                    profileCount: session.profiles.count,
                    availableApps: slots.availableApps,
                    onOpen: { app, anchor in
                        model.appAnchor = anchor
                        open(app)
                    },
                    onUnlock: { runDeviceUnlock(thenOpen: $0) },
                    onMove: { model.move(itemID: $0, onto: $1) },
                    onClose: { navigator.showFaces() }
                )
                .allowsHitTesting(surface == .homeScreen)
                .accessibilityHidden(surface != .homeScreen)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if case .app(let app) = surface {
                // The app grows out of its icon and shrinks back into it.
                AppHostView(app: app, slots: slots) { navigator.back() }
                    .transition(.scale(scale: 0.06, anchor: model.appAnchor).combined(with: .opacity))
                    .zIndex(1)
            }

            if !needsWelcome {
                chrome(surface: surface, audience: audience, metrics: metrics, isApart: isApart)
                    .zIndex(2)
            }

            if let overlay = state.overlay, overlay != .assistant {
                overlayView(overlay, preferences: preferences)
                    .zIndex(4)
            }

            alerts
                .zIndex(5)

            if needsWelcome {
                HelloOverlay(
                    onAddPeople: {
                        model.helloDismissed = true
                        open(.people)
                    },
                    onDismiss: { model.helloDismissed = true }
                )
                .transition(.opacity)
                .zIndex(6)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.touch() })
    }

    /// What floats over a face and the Home Screen: the live pill at the top center, the status
    /// in the top trailing corner, and the bar at the bottom. An app keeps only the bar.
    private func chrome(surface: HubSurface, audience: AudienceContext, metrics: HubMetrics, isApart: Bool) -> some View {
        let isApp: Bool = if case .app = surface { true } else { false }
        let motion = HubMotion(reducesMotion: reduceMotion, slowdown: hooks.slowMotion ?? 1)
        return ZStack {
            if !isApp {
                TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
                    LivePillView(
                        items: pillItems(audience),
                        maxWidth: metrics.width - 2 * (model.statusWidth + metrics.margin + metrics.gutter),
                        availableApps: slots.availableApps,
                        isExpanded: $model.isPillExpanded
                    ) { open($0) }
                }
                .padding(.top, metrics.topEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if !isApart, !model.isPillExpanded {
                    StatusCluster(
                        profile: session.activeProfile,
                        isSomeonePresent: session.isSomeonePresent,
                        indicator: slots.recognitionIndicator,
                        showsAssistant: isAssistantAvailable,
                        onControlCenter: { send(.swipeDownFromTopTrailing) },
                        onUnlock: { runDeviceUnlock(thenOpen: nil) },
                        onAssistant: { send(.openAssistant) }
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.statusWidth = $0 }
                    .padding(.top, metrics.topEdge)
                    .padding(.trailing, metrics.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                }
            }
            HomeBar(leadsToFace: surface == .homeScreen) {
                model.touch()
                surface == .homeScreen ? navigator.showFaces() : navigator.showHomeScreen()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(motion.snappy, value: model.isPillExpanded)
        .transition(.opacity)
    }

    /// The live things for the pill. Do Not Disturb holds back what other packages report;
    /// the hub's own timers and music stay.
    private func pillItems(_ audience: AudienceContext) -> [LivePillItem] {
        LivePill.items(
            recognizedName: model.recognizedName,
            timers: environment.timers.strip,
            nowPlaying: environment.music.nowPlaying,
            extras: model.isQuiet() ? [] : slots.liveItems(),
            context: audience
        )
    }

    @ViewBuilder
    private func overlayView(_ overlay: HubOverlay, preferences: HubPreferences) -> some View {
        let dismiss: () -> Void = { navigator.dismissOverlay() }
        let snapshot = environment.home.snapshot
        switch overlay {
        case .controlCenter:
            ControlCenterView(
                session: session,
                isNight: model.night.isNight,
                isQuiet: model.isQuiet(),
                brightness: model.brightness,
                showsIntercom: slots.intercom != nil && !session.isGuest,
                showsAssistant: isAssistantAvailable,
                showsSetupHint: VisibilityPolicy.needsSetupHint(profileCount: session.profiles.count, setupMode: preferences.setupMode),
                onNight: {
                    model.toggleNight(schedule: preferences.night, ambient: ambientLight?(), now: Date(), calendar: calendar)
                    model.readBrightness()
                },
                onQuiet: {
                    model.toggleQuiet(schedule: preferences.night, now: Date(), calendar: calendar)
                    applyQuiet()
                },
                onBrightness: { model.setBrightness($0) },
                onOpen: { open($0) },
                onAssistant: { send(.openAssistant) },
                onUnlock: { runDeviceUnlock(thenOpen: nil) },
                onClose: dismiss
            )
            .transition(.opacity.combined(with: .scale(scale: 1.06)))
        case .facePicker:
            FacePickerView(faces: preferences.faces.enabledFaces, selection: $model.face, facePosition: facePosition) { kind in
                model.face = kind
                send(.chooseFace)
            }
            .transition(.opacity)
        case .inlineControl(.thermostat(let id)):
            if let thermostat = snapshot.thermostats.first(where: { $0.id == id }) {
                ThermostatDialView(thermostat: thermostat, onClose: dismiss)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                OverlayScrim(onDismiss: dismiss)
            }
        case .inlineControl(.dimmer(let id)):
            if let accessory = snapshot.accessories.first(where: { $0.id == id }) {
                DimmerView(accessory: accessory, onClose: dismiss)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                OverlayScrim(onDismiss: dismiss)
            }
        case .inlineControl(.camera(let id)):
            if let camera = snapshot.cameras.first(where: { $0.id == id }) {
                CameraZoomView(camera: camera, onClose: dismiss)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                OverlayScrim(onDismiss: dismiss)
            }
        case .assistant:
            EmptyView()
        }
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

    /// Everything a gesture or a tap asks of the hub goes through the state machine.
    private func send(_ event: HubEvent) {
        model.touch()
        switch event {
        case .tapApp(let app):
            open(app)
        case .openAssistant where !isAssistantAvailable:
            break
        case .swipeDownFromTopTrailing:
            model.readBrightness()
            model.isPillExpanded = false
            navigator.handle(event, context: currentAudience)
        default:
            navigator.handle(event, context: currentAudience)
        }
    }

    private func open(_ app: HubApp) {
        model.touch()
        if app == .settings {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
            return
        }
        navigator.open(app, context: currentAudience)
    }

    /// Do Not Disturb reaches the timer and alarm sounds here, and the app through the
    /// navigator, which holds its own banners back.
    private func applyQuiet() {
        let isQuiet = model.isQuiet()
        environment.timers.isSilenced = isQuiet
        environment.alarms.isSilenced = isQuiet
        navigator.isDoNotDisturbOn = isQuiet
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
            let context = currentAudience
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
        guard navigator.state.canChangeFace else { return .ignored }
        model.touch()
        withAnimation(HubMotion(reducesMotion: reduceMotion).spring) {
            model.step(step, enabledFaces: preferences.faces.enabledFaces)
        }
        return .handled
    }

    /// Swipes that start at an edge: up from the bottom, down from the top, down from the top
    /// trailing corner, and down from the top center. Everything else is left to the face
    /// pager and to scrolling.
    private func edgeSwipe(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            model.touch()
            let event = HubGesture.event(
                startX: Double(value.startLocation.x),
                startY: Double(value.startLocation.y),
                translationX: Double(value.translation.width),
                translationY: Double(value.translation.height),
                width: Double(size.width),
                height: Double(size.height),
                isAssistantAvailable: isAssistantAvailable
            )
            if let event {
                send(event)
            }
        }
    }

    /// Runs every few seconds while the hub is in front: Night Mode, Do Not Disturb, drifting
    /// back to the face, and telling companions what is showing.
    private func housekeeping() {
        let now = Date()
        let preferences = currentPreferences
        model.updateNight(schedule: preferences.night, ambient: ambientLight?(), now: now, calendar: calendar, forced: hooks.forcesNight)
        applyQuiet()
        navigator.handle(
            .idle(
                seconds: now.timeIntervalSince(model.lastInteraction),
                isMediaPlaying: environment.music.nowPlaying?.isPlaying ?? false,
                timeout: preferences.idleReturn
            ),
            context: currentAudience
        )
        guard let onSummaryChange, let face = model.face else { return }
        let summary = HubStatusSummary(
            surface: navigator.state.surface,
            face: face,
            profileName: session.activeProfile?.name,
            timers: environment.timers.engine.timers,
            nowPlaying: environment.music.nowPlaying,
            isNight: model.night.isNight,
            at: now
        )
        if let changed = model.summaryIfChanged(summary) {
            onSummaryChange(changed)
        }
    }
}

/// A stand-in for the assistant, for UI tests and previews: enough to see where the real one
/// will be drawn and that it can be closed.
enum SampleAssistant {
    @MainActor static let slot = HubAssistant(isAvailable: { true }) { dismiss in
        AnyView(SampleAssistantView(dismiss: dismiss))
    }
}

private struct SampleAssistantView: View {
    let dismiss: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: [.purple, .blue, .pink, .orange, .purple], center: .center),
                    lineWidth: 10
                )
                .blur(radius: 6)
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                Text("Assistant")
                    .font(.title2.weight(.semibold))
                Text("The assistant draws here.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(36)
            .hubGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Assistant")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("assistant.sample")
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

/// The faces side by side. Swiping left or right moves between them, each sliding in with a
/// little depth.
struct FacePagerView: View {
    let faces: [FaceKind]
    @Binding var selection: FaceKind?
    let facePosition: (@MainActor () -> FacePosition?)?
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubMayPrompt) private var mayPrompt
    @Environment(\.hubMotion) private var motion

    var body: some View {
        let reducesMotion = motion.reducesMotion
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(faces) { kind in
                    FaceView(kind: kind, facePosition: facePosition)
                        .frame(width: metrics.width, height: metrics.height)
                        .clipped()
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity || reducesMotion ? 1 : 0.9)
                                .opacity(phase.isIdentity ? 1 : 0.5)
                        }
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
        .accessibilityHint("Swipe left or right to change the face. Swipe up from the bottom edge for the Home Screen. Touch and hold to choose a face.")
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
