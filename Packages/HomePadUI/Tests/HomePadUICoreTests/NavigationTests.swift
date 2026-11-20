import Foundation
import Testing
@testable import HomePadUICore

@Suite struct HubNavigationTests {
    private let guest = AudienceContext(isGuest: true, isPersonalContentUnlocked: false, setupMode: false)
    private let unlocked = AudienceContext(isGuest: false, isPersonalContentUnlocked: true, setupMode: false)

    @Test func back_whenInApp_thenHomeScreenThenFaces() {
        var state = HubNavigationState()
        state.showHomeScreen()
        let opened = state.open(.timers, context: guest)
        #expect(opened)
        #expect(state.surface == .app(.timers))
        state.back()
        #expect(state.surface == .homeScreen)
        state.back()
        #expect(state.surface == .faces)
        state.back()
        #expect(state.surface == .faces)
        state.showHomeScreen()
        state.showFaces()
        #expect(state.surface == .faces)
    }

    @Test func open_whenAudienceMayNotSeeApp_thenStaysPut() {
        var state = HubNavigationState(surface: .homeScreen)
        let refused = state.open(.projectedApps, context: guest)
        #expect(!refused)
        #expect(state.surface == .homeScreen)
        let allowed = state.open(.projectedApps, context: unlocked)
        #expect(allowed)
    }

    @Test func audienceChanged_whenOwnerWalksAway_thenPersonalAppCloses() {
        var state = HubNavigationState()
        state.open(.projectedApps, context: unlocked)
        state.audienceChanged(guest)
        #expect(state.surface == .homeScreen)
        state.open(.timers, context: guest)
        state.audienceChanged(guest)
        #expect(state.surface == .app(.timers))
        state.showFaces()
        state.audienceChanged(guest)
        #expect(state.surface == .faces)
    }

    @Test func takeover_whenPresented_thenBackDismissesItFirst() {
        var state = HubNavigationState(surface: .app(.music))
        state.presentTakeover()
        #expect(state.isTakeoverPresented)
        state.back()
        #expect(!state.isTakeoverPresented)
        #expect(state.surface == .app(.music))
        state.presentTakeover()
        state.dismissTakeover()
        #expect(!state.isTakeoverPresented)
    }

    @Test func idle_whenNoTouchForTheTimeout_thenHomeScreenAndAppsReturnToFace() {
        var state = HubNavigationState(surface: .homeScreen)
        let changed1 = state.handle(.idle(seconds: 30, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(!changed1)
        #expect(state.surface == .homeScreen)
        let changed2 = state.handle(.idle(seconds: 120, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(changed2)
        #expect(state.surface == .faces)
        let changed3 = state.handle(.idle(seconds: 900, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(!changed3)
        var weather = HubNavigationState(surface: .app(.weather))
        weather.handle(.idle(seconds: 121, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(weather.surface == .faces)
    }

    @Test func idle_whenMediaPlaysOrHandsFreeAppOrNever_thenStays() {
        var music = HubNavigationState(surface: .app(.music))
        music.handle(.idle(seconds: 900, isMediaPlaying: true, timeout: 120), context: guest)
        #expect(music.surface == .app(.music))
        music.handle(.idle(seconds: 900, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(music.surface == .faces)
        for app in [HubApp.recipes, .mirror] {
            var state = HubNavigationState(surface: .app(app))
            state.handle(.idle(seconds: 900, isMediaPlaying: false, timeout: 120), context: guest)
            #expect(state.surface == .app(app))
        }
        var never = HubNavigationState(surface: .homeScreen)
        never.handle(.idle(seconds: 9000, isMediaPlaying: false, timeout: nil), context: guest)
        #expect(never.surface == .homeScreen)
        var takeover = HubNavigationState(surface: .homeScreen, isTakeoverPresented: true)
        takeover.handle(.idle(seconds: 900, isMediaPlaying: false, timeout: 120), context: guest)
        #expect(takeover.surface == .homeScreen)
    }

    @Test func idle_whenOverlayIsOpen_thenItCloses() {
        var state = HubNavigationState(surface: .faces, overlay: .controlCenter)
        let changed4 = state.handle(.idle(seconds: 200, isMediaPlaying: true, timeout: 120), context: guest)
        #expect(changed4)
        #expect(state.overlay == nil && state.surface == .faces)
    }

    @Test func longPress_whenOnAFaceWithNothingOver_thenFacePickerAndChoosingClosesIt() {
        var state = HubNavigationState()
        #expect(state.canChangeFace)
        let changed5 = state.handle(.longPressCanvas, context: guest)
        #expect(changed5)
        #expect(state.overlay == .facePicker)
        #expect(!state.canChangeFace)
        let changed6 = state.handle(.longPressCanvas, context: guest)
        #expect(!changed6)
        let changed7 = state.handle(.chooseFace, context: guest)
        #expect(changed7)
        #expect(state.overlay == nil && state.surface == .faces)
        var home = HubNavigationState(surface: .homeScreen)
        let changed8 = home.handle(.longPressCanvas, context: guest)
        #expect(!changed8)
        let changed9 = home.handle(.chooseFace, context: guest)
        #expect(!changed9)
        home.present(.facePicker)
        #expect(home.overlay == nil)
        var control = HubNavigationState(overlay: .controlCenter)
        let changed10 = control.handle(.chooseFace, context: guest)
        #expect(!changed10)
        #expect(control.overlay == .controlCenter)
    }

    @Test func swipeUpFromBottom_whenOnFaceOrInApp_thenHomeScreen() {
        var state = HubNavigationState()
        let changed11 = state.handle(.swipeUpFromBottomEdge, context: guest)
        #expect(changed11)
        #expect(state.surface == .homeScreen)
        let changed12 = state.handle(.swipeUpFromBottomEdge, context: guest)
        #expect(!changed12)
        var app = HubNavigationState(surface: .app(.music))
        app.handle(.swipeUpFromBottomEdge, context: guest)
        #expect(app.surface == .homeScreen)
    }

    @Test func swipeUpFromBottom_whenSomethingIsOver_thenThatClosesFirst() {
        var state = HubNavigationState(surface: .faces, overlay: .controlCenter, isTakeoverPresented: true)
        state.handle(.swipeUpFromBottomEdge, context: guest)
        #expect(!state.isTakeoverPresented && state.overlay == .controlCenter)
        state.handle(.swipeUpFromBottomEdge, context: guest)
        #expect(state.overlay == nil && state.surface == .faces)
    }

    @Test func swipeDown_whenOnHomeScreen_thenFaceAndNothingElsewhere() {
        var state = HubNavigationState(surface: .homeScreen)
        let changed13 = state.handle(.swipeDown, context: guest)
        #expect(changed13)
        #expect(state.surface == .faces)
        let changed14 = state.handle(.swipeDown, context: guest)
        #expect(!changed14)
        var app = HubNavigationState(surface: .app(.timers))
        let changed15 = app.handle(.swipeDown, context: guest)
        #expect(!changed15)
        var covered = HubNavigationState(surface: .homeScreen, overlay: .controlCenter)
        let changed16 = covered.handle(.swipeDown, context: guest)
        #expect(!changed16)
        var taken = HubNavigationState(surface: .homeScreen, isTakeoverPresented: true)
        let changed17 = taken.handle(.swipeDown, context: guest)
        #expect(!changed17)
    }

    @Test func overlays_whenOpenedFromAnySurface_thenSurfaceStaysAndDismissCloses() {
        for surface in [HubSurface.faces, .homeScreen, .app(.home)] {
            var state = HubNavigationState(surface: surface)
            let changed18 = state.handle(.swipeDownFromTopTrailing, context: guest)
            #expect(changed18)
            #expect(state.overlay == .controlCenter && state.surface == surface)
            let changed19 = state.handle(.openAssistant, context: guest)
            #expect(changed19)
            #expect(state.overlay == .assistant)
            let changed20 = state.handle(.tapInlineControl(.thermostat(id: "t")), context: guest)
            #expect(changed20)
            #expect(state.overlay == .inlineControl(.thermostat(id: "t")))
            state.handle(.tapInlineControl(.dimmer(id: "l")), context: guest)
            #expect(state.overlay == .inlineControl(.dimmer(id: "l")))
            state.handle(.tapInlineControl(.camera(id: "c")), context: guest)
            #expect(state.overlay == .inlineControl(.camera(id: "c")))
            let changed21 = state.handle(.dismissOverlay, context: guest)
            #expect(changed21)
            #expect(state.overlay == nil && state.surface == surface)
            state.present(.controlCenter)
            state.dismissOverlay()
            #expect(state.overlay == nil)
        }
    }

    @Test func overlays_whenATakeoverIsUp_thenNothingOpensOverIt() {
        var state = HubNavigationState(isTakeoverPresented: true)
        let changed22 = state.handle(.swipeDownFromTopTrailing, context: guest)
        #expect(!changed22)
        #expect(state.overlay == nil)
        #expect(!state.canChangeFace)
    }

    @Test func tapApp_whenAllowed_thenOpensAndClosesAnyOverlay() {
        var state = HubNavigationState(surface: .faces, overlay: .controlCenter)
        let changed23 = state.handle(.tapApp(.timers), context: guest)
        #expect(changed23)
        #expect(state.surface == .app(.timers) && state.overlay == nil)
        let changed24 = state.handle(.tapApp(.projectedApps), context: guest)
        #expect(!changed24)
        #expect(state.surface == .app(.timers))
        state.present(.controlCenter)
        state.back()
        #expect(state.overlay == nil && state.surface == .app(.timers))
        state.present(.controlCenter)
        state.showHomeScreen()
        #expect(state.overlay == nil && state.surface == .homeScreen)
        state.present(.controlCenter)
        state.showFaces()
        #expect(state.overlay == nil && state.surface == .faces)
    }
}

@Suite struct HubOutsideRequestTests {
    @Test func showFace_whenTheFaceIsOn_thenFacesComeToTheFrontOverEverythingButTheAssistant() {
        var state = HubNavigationState(surface: .app(.music), overlay: .controlCenter, isTakeoverPresented: true)
        let shown = state.showFace(.weather, enabled: [.weather, .flow])
        #expect(shown)
        #expect(state == HubNavigationState(surface: .faces))
        var asking = HubNavigationState(surface: .homeScreen, overlay: .assistant)
        asking.showFace(.flow, enabled: [.weather, .flow])
        #expect(asking == HubNavigationState(surface: .faces, overlay: .assistant))
    }

    @Test func showFace_whenTheFaceIsOff_thenNothingChanges() {
        var state = HubNavigationState(surface: .app(.music), overlay: .controlCenter)
        let shown = state.showFace(.rainbow, enabled: [.weather, .flow])
        #expect(!shown)
        #expect(state == HubNavigationState(surface: .app(.music), overlay: .controlCenter))
        // With every face off the hub rests on Digital, so that is the one face it can show.
        var bare = HubNavigationState(surface: .homeScreen)
        let digital = bare.showFace(.digital, enabled: [])
        #expect(digital && bare.surface == .faces)
    }

    @Test func screen_whenAsked_thenTheFrontmostThing() {
        #expect(HubNavigationState().screen(face: .flow) == .face(.flow))
        #expect(HubNavigationState().screen(face: nil) == .face(nil))
        #expect(HubNavigationState(surface: .homeScreen).screen(face: .flow) == .homeScreen)
        #expect(HubNavigationState(surface: .app(.timers)).screen(face: .flow) == .app(.timers))
        #expect(HubNavigationState(surface: .app(.timers), overlay: .controlCenter).screen(face: .flow) == .overlay(.controlCenter))
        #expect(HubNavigationState(surface: .faces, overlay: .assistant, isTakeoverPresented: true).screen(face: .flow) == .takeover)
    }
}

@Suite struct HubSignOutTests {
    @Test func signedOut_whenAPageOrTheBrowserOrAPersonalAppIsInFront_thenItGivesWayToTheFace() {
        var takeover = HubNavigationState(surface: .app(.timers), isTakeoverPresented: true)
        takeover.audienceSignedOut()
        #expect(takeover == HubNavigationState(surface: .app(.timers)))
        var browser = HubNavigationState(surface: .app(.beam), overlay: .controlCenter)
        browser.audienceSignedOut()
        #expect(browser == HubNavigationState(surface: .faces))
        var personal = HubNavigationState(surface: .app(.projectedApps))
        personal.audienceSignedOut()
        #expect(personal.surface == .faces)
    }

    @Test func signedOut_whenNothingOfTheirsIsInFront_thenNothingMoves() {
        var music = HubNavigationState(surface: .app(.music), overlay: .controlCenter)
        music.audienceSignedOut()
        #expect(music == HubNavigationState(surface: .app(.music), overlay: .controlCenter))
        var home = HubNavigationState(surface: .homeScreen)
        home.audienceSignedOut()
        #expect(home.surface == .homeScreen)
        var face = HubNavigationState(overlay: .facePicker)
        face.audienceSignedOut()
        #expect(face == HubNavigationState(overlay: .facePicker))
    }
}

@Suite struct HubGestureTests {
    private func event(x: Double, y: Double, dx: Double = 0, dy: Double, assistant: Bool = false) -> HubEvent? {
        HubGesture.event(startX: x, startY: y, translationX: dx, translationY: dy, width: 1000, height: 800, isAssistantAvailable: assistant)
    }

    @Test func swipeUp_whenItStartsAtTheBottomEdge_thenHomeScreenOtherwiseNothing() {
        #expect(event(x: 500, y: 780, dy: -200) == .swipeUpFromBottomEdge)
        #expect(event(x: 500, y: 800 * (1 - HubGesture.bottomEdgeFraction), dy: -200) == .swipeUpFromBottomEdge)
        #expect(event(x: 500, y: 600, dy: -200) == nil)
    }

    @Test func swipeDown_whenItStartsAtTheTopEdge_thenByWhereAlongIt() {
        #expect(event(x: 100, y: 10, dy: 200) == .swipeDown)
        #expect(event(x: 900, y: 10, dy: 200) == .swipeDownFromTopTrailing)
        #expect(event(x: 1000 * (1 - HubGesture.trailingCornerFraction), y: 10, dy: 200) == .swipeDownFromTopTrailing)
        #expect(event(x: 500, y: 10, dy: 200) == .swipeDown)
        #expect(event(x: 500, y: 10, dy: 200, assistant: true) == .openAssistant)
        #expect(event(x: 360, y: 10, dy: 200, assistant: true) == .openAssistant)
        #expect(event(x: 300, y: 10, dy: 200, assistant: true) == .swipeDown)
        #expect(event(x: 900, y: 10, dy: 200, assistant: true) == .swipeDownFromTopTrailing)
        #expect(event(x: 500, y: 400, dy: 200) == nil)
    }

    @Test func startsOverlay_whenADragBeginsInTheTopTrailingCornerOrTheAssistantsZone_thenTrue() {
        func starts(x: Double, y: Double, assistant: Bool) -> Bool {
            HubGesture.startsOverlay(startX: x, startY: y, width: 1000, height: 800, isAssistantAvailable: assistant)
        }
        #expect(starts(x: 900, y: 10, assistant: false))
        #expect(starts(x: 500, y: 10, assistant: true))
        #expect(!starts(x: 500, y: 10, assistant: false))
        #expect(!starts(x: 100, y: 10, assistant: true))
        #expect(!starts(x: 900, y: 400, assistant: true))
    }

    @Test func drag_whenShortOrSideways_thenNothing() {
        #expect(event(x: 500, y: 780, dy: -40) == nil)
        #expect(event(x: 500, y: 780, dx: 150, dy: -200) == nil)
        #expect(event(x: 500, y: 10, dx: -300, dy: 100) == nil)
    }
}

@Suite struct CanvasLayoutTests {
    @Test func layout_whenFill_thenTheWholeSpaceWithSquareCorners() {
        let layout = CanvasLayout(width: 1366, height: 1024, mode: .fill)
        #expect(layout.canvas == CanvasFrame(x: 0, y: 0, width: 1366, height: 1024))
        #expect(!layout.isInset && layout.cornerRadius == 0)
        let empty = CanvasLayout(width: -4, height: -9, mode: .fill)
        #expect(empty.canvas == CanvasFrame(x: 0, y: 0, width: 0, height: 0))
    }

    @Test func layout_whenSquare_thenCenteredOnTheShorterSideWithRoundedCorners() {
        let landscape = CanvasLayout(width: 1366, height: 1024, mode: .square)
        #expect(landscape.canvas == CanvasFrame(x: 171, y: 0, width: 1024, height: 1024))
        #expect(landscape.isInset)
        #expect(abs(landscape.cornerRadius - 102.4) < 1e-9)
        let portrait = CanvasLayout(width: 1024, height: 1366, mode: .square)
        #expect(portrait.canvas == CanvasFrame(x: 0, y: 171, width: 1024, height: 1024))
        let exact = CanvasLayout(width: 600, height: 600, mode: .square)
        #expect(!exact.isInset && exact.cornerRadius == 0)
    }
}

@Suite struct HubSummaryTests {
    @Test func summary_whenAppOpenWithTimersAndMusic_thenCountsRunningAndNamesTrack() throws {
        let now = Fixtures.date()
        let timers = [
            HubTimer(name: "a", duration: 60, state: .running(endsAt: now.addingTimeInterval(60)), createdAt: now),
            HubTimer(name: "b", duration: 60, state: .running(endsAt: now.addingTimeInterval(20)), createdAt: now),
            HubTimer(name: "c", duration: 60, state: .paused(remaining: 5), createdAt: now),
        ]
        let summary = HubStatusSummary(surface: .app(.recipes), face: .flow, profileName: "Erica", timers: timers, nowPlaying: NowPlaying(title: "Song", isPlaying: true), isNight: false, at: now)
        #expect(summary.app == .recipes && !summary.showsHomeScreen)
        #expect(summary.runningTimers == 2)
        #expect(summary.nextTimerEnd == now.addingTimeInterval(20))
        #expect(summary.nowPlayingTitle == "Song")
        #expect(summary.isFresh(at: now.addingTimeInterval(100)))
        #expect(!summary.isFresh(at: now.addingTimeInterval(500)))
        let decoded = try JSONDecoder().decode(HubStatusSummary.self, from: JSONEncoder().encode(summary))
        #expect(decoded == summary)
    }

    @Test func summary_whenOnHomeScreenAndPaused_thenNoAppAndNoTrack() {
        let summary = HubStatusSummary(surface: .homeScreen, face: .analog, profileName: nil, timers: [], nowPlaying: NowPlaying(title: "Song", isPlaying: false), isNight: true, at: Fixtures.date())
        #expect(summary.showsHomeScreen && summary.app == nil)
        #expect(summary.nowPlayingTitle == nil && summary.nextTimerEnd == nil && summary.isNight)
        let none = HubStatusSummary(surface: .faces, face: .analog, profileName: nil, timers: [], nowPlaying: nil, isNight: false, at: Fixtures.date())
        #expect(none.nowPlayingTitle == nil && !none.showsHomeScreen)
    }
}
