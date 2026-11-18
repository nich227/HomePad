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
        let refused = state.open(.messages, context: guest)
        #expect(!refused)
        #expect(state.surface == .homeScreen)
        let allowed = state.open(.messages, context: unlocked)
        #expect(allowed)
    }

    @Test func audienceChanged_whenOwnerWalksAway_thenPersonalAppCloses() {
        var state = HubNavigationState()
        state.open(.messages, context: unlocked)
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

    @Test func restIfIdle_whenNobodyThereLongEnough_thenReturnsToFace() {
        var state = HubNavigationState(surface: .homeScreen)
        state.restIfIdle(isSomeonePresent: true, idleSeconds: 500)
        #expect(state.surface == .homeScreen)
        state.restIfIdle(isSomeonePresent: false, idleSeconds: 30)
        #expect(state.surface == .homeScreen)
        state.restIfIdle(isSomeonePresent: false, idleSeconds: 90)
        #expect(state.surface == .faces)
        state.restIfIdle(isSomeonePresent: false, idleSeconds: 900)
        #expect(state.surface == .faces)
        var weather = HubNavigationState(surface: .app(.weather))
        weather.restIfIdle(isSomeonePresent: false, idleSeconds: 91)
        #expect(weather.surface == .faces)
    }

    @Test func restIfIdle_whenCookingOrTakeover_thenStays() {
        for app in [HubApp.recipes, .music, .timers, .mirror] {
            var state = HubNavigationState(surface: .app(app))
            state.restIfIdle(isSomeonePresent: false, idleSeconds: 900)
            #expect(state.surface == .app(app))
        }
        var takeover = HubNavigationState(surface: .homeScreen, isTakeoverPresented: true)
        takeover.restIfIdle(isSomeonePresent: false, idleSeconds: 900)
        #expect(takeover.surface == .homeScreen)
    }

    @Test func swipe_whenMostlyVerticalPastThreshold_thenUpOrDown() {
        #expect(SwipeDecision.vertical(translationX: 5, translationY: -120) == .up)
        #expect(SwipeDecision.vertical(translationX: -10, translationY: 90) == .down)
        #expect(SwipeDecision.vertical(translationX: 100, translationY: -120) == nil)
        #expect(SwipeDecision.vertical(translationX: 0, translationY: -20) == nil)
    }
}

@Suite struct CanvasLayoutTests {
    @Test func layout_whenSquareMode_thenCenteredOnShortSide() {
        let layout = CanvasLayout(width: 1366, height: 1024, mode: .square)
        #expect(layout.square == CanvasFrame(x: 171, y: 0, width: 1024, height: 1024))
        #expect(layout.side == nil)
        let portrait = CanvasLayout(width: 1024, height: 1366, mode: .square, margin: 12)
        #expect(portrait.square == CanvasFrame(x: 12, y: 183, width: 1000, height: 1000))
    }

    @Test func status_whenSquareHasBlackBeside_thenStatusSitsInThatMarginNotOnTheSquare() {
        let landscape = CanvasLayout(width: 1366, height: 1024, mode: .square)
        #expect(landscape.status == CanvasFrame(x: 1195, y: 0, width: 171, height: 1024))
        let portrait = CanvasLayout(width: 1024, height: 1366, mode: .square)
        #expect(portrait.status == CanvasFrame(x: 0, y: 0, width: 1024, height: 171))
    }

    @Test func status_whenSquareFillsTheWindow_thenNoStatus() {
        #expect(CanvasLayout(width: 1000, height: 1040, mode: .square).status == nil)
        #expect(CanvasLayout(width: 1040, height: 1000, mode: .square).status == nil)
        #expect(CanvasLayout(width: 0, height: 0, mode: .square).status == nil)
    }

    @Test func status_whenFill_thenStatusTakesAStripOfTheSecondColumn() {
        let landscape = CanvasLayout(width: 1400, height: 1000, mode: .fill)
        #expect(landscape.status == CanvasFrame(x: 1000, y: 0, width: 400, height: 130))
        #expect(landscape.side == CanvasFrame(x: 1000, y: 130, width: 400, height: 870))
        let portrait = CanvasLayout(width: 1000, height: 1400, mode: .fill)
        #expect(portrait.status == CanvasFrame(x: 870, y: 1000, width: 130, height: 400))
        #expect(portrait.side == CanvasFrame(x: 0, y: 1000, width: 870, height: 400))
    }

    @Test func layout_whenFillLandscape_thenSquareLeadingAndSideColumn() {
        let layout = CanvasLayout(width: 1366, height: 1024, mode: .fill, margin: 0, gap: 16)
        #expect(layout.square == CanvasFrame(x: 0, y: 0, width: 1024, height: 1024))
        #expect(layout.side?.x == 1040 && layout.side?.width == 326)
        #expect(layout.status?.x == 1040 && layout.status?.y == 0)
    }

    @Test func layout_whenFillPortrait_thenSideGoesBelow() {
        let layout = CanvasLayout(width: 800, height: 1200, mode: .fill, gap: 10)
        #expect(layout.square == CanvasFrame(x: 0, y: 0, width: 800, height: 800))
        #expect(layout.side == CanvasFrame(x: 0, y: 810, width: 696, height: 390))
    }

    @Test func layout_whenFillButLeftoverTooSmall_thenCenteredWithoutSide() {
        let layout = CanvasLayout(width: 1100, height: 1000, mode: .fill)
        #expect(layout.side == nil)
        #expect(layout.square.x == 50)
        let tiny = CanvasLayout(width: 10, height: 10, mode: .fill, margin: 20)
        #expect(tiny.square.width == 0)
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
