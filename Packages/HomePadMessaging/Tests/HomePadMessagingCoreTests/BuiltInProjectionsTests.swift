import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct AgendaProjectionTests {
    /// Also checks that the hub would accept what the builder produced.
    private func build(_ items: [AgendaItem], now: Date = Fixture.t0) throws -> AgendaTemplate {
        let template = AgendaProjection.template(id: "calendar.root", title: "Calendar", emptyMessage: "Nothing coming up", items: items, untitled: "Untitled", now: now)
        try ProjectionValidator().validate(template)
        guard case .agenda(let agenda) = template else { throw CancellationError() }
        return agenda
    }

    @Test func toggleActionID_whenRoundTripped_thenRecoversItemID() {
        #expect(AgendaProjection.itemID(fromToggleActionID: AgendaProjection.toggleActionID(itemID: "abc")) == "abc")
        #expect(AgendaProjection.itemID(fromToggleActionID: "agenda.toggle.") == nil)
        #expect(AgendaProjection.itemID(fromToggleActionID: "other.toggle.abc") == nil)
    }

    @Test func template_whenItemsUnordered_thenSortedByStartWithUndatedLast() throws {
        let agenda = try build([
            AgendaItem(id: "undatedB", kind: .reminder, title: "B"),
            AgendaItem(id: "late", kind: .event, title: "Late", start: Fixture.t0.addingTimeInterval(7200), end: Fixture.t0.addingTimeInterval(9000)),
            AgendaItem(id: "undatedA", kind: .reminder, title: "A"),
            AgendaItem(id: "early", kind: .event, title: "Early", start: Fixture.t0.addingTimeInterval(60), end: Fixture.t0.addingTimeInterval(120)),
            AgendaItem(id: "sameZ", kind: .reminder, title: "Z", start: Fixture.t0.addingTimeInterval(60)),
        ])
        #expect(agenda.entries.map(\.id) == ["early", "sameZ", "late", "undatedA", "undatedB"])
        #expect(agenda.emptyMessage == "Nothing coming up")
        #expect(agenda.title == "Calendar")
    }

    @Test func template_whenEventHasEnded_thenDroppedButRemindersStay() throws {
        let agenda = try build([
            AgendaItem(id: "over", kind: .event, title: "Over", start: Fixture.t0.addingTimeInterval(-7200), end: Fixture.t0),
            AgendaItem(id: "running", kind: .event, title: "Running", start: Fixture.t0.addingTimeInterval(-60), end: Fixture.t0.addingTimeInterval(60)),
            AgendaItem(id: "overdue", kind: .reminder, title: "Overdue", start: Fixture.t0.addingTimeInterval(-7200), end: Fixture.t0.addingTimeInterval(-7200)),
            AgendaItem(id: "openEnded", kind: .event, title: "Open"),
        ])
        #expect(Set(agenda.entries.map(\.id)) == ["running", "overdue", "openEnded"])
    }

    @Test func template_whenReminder_thenHasToggleActionAndEventsDoNot() throws {
        let agenda = try build([
            AgendaItem(id: "r", kind: .reminder, title: "Milk", detail: "Groceries", isCompleted: true),
            AgendaItem(id: "e", kind: .event, title: "Lunch", start: Fixture.t0.addingTimeInterval(60), end: Fixture.t0.addingTimeInterval(120), isAllDay: true, detail: "Cafe"),
        ])
        let reminder = agenda.entries.first { $0.id == "r" }
        let event = agenda.entries.first { $0.id == "e" }
        #expect(reminder?.actionID == "agenda.toggle.r")
        #expect(reminder?.isCompleted == true)
        #expect(reminder?.detail == "Groceries")
        #expect(event?.actionID == nil)
        #expect(event?.isAllDay == true)
    }

    @Test func template_whenIDsUnusableOrRepeated_thenThoseItemsAreLeftOut() throws {
        let agenda = try build([
            AgendaItem(id: "", kind: .reminder, title: "Empty"),
            AgendaItem(id: "has space", kind: .reminder, title: "Space"),
            AgendaItem(id: String(repeating: "x", count: 128), kind: .reminder, title: "Long"),
            AgendaItem(id: "ok", kind: .reminder, title: "First"),
            AgendaItem(id: "ok", kind: .reminder, title: "Second"),
        ])
        #expect(agenda.entries.map(\.title) == ["First"])
    }

    @Test func template_whenTextTooLongOrBlank_thenTrimmedToLimitsOrGivenPlaceholder() throws {
        let agenda = try build([
            AgendaItem(id: "a", kind: .reminder, title: String(repeating: "t", count: 200), detail: String(repeating: "d", count: 400)),
            AgendaItem(id: "b", kind: .reminder, title: "   "),
        ])
        #expect(agenda.entries.first { $0.id == "a" }?.title.count == 80)
        #expect(agenda.entries.first { $0.id == "a" }?.detail?.count == 160)
        #expect(agenda.entries.first { $0.id == "b" }?.title == "Untitled")
    }

    @Test func template_whenMoreItemsThanLimit_thenKeepsTheEarliest() throws {
        let items = (0..<30).map { AgendaItem(id: "e\($0)", kind: .reminder, title: "E", start: Fixture.t0.addingTimeInterval(Double(30 - $0))) }
        let agenda = try build(items)
        #expect(agenda.entries.count == 24)
        #expect(agenda.entries.first?.id == "e29")
    }
}

@Suite struct NowPlayingProjectionTests {
    /// Also checks that the hub would accept what the builder produced.
    private func build(_ snapshot: NowPlayingSnapshot) throws -> NowPlayingTemplate {
        let template = NowPlayingProjection.template(snapshot: snapshot, idleTitle: "Not Playing")
        try ProjectionValidator().validate(template)
        guard case .nowPlaying(let value) = template else { throw CancellationError() }
        return value
    }

    @Test func template_whenNothingIsPlaying_thenIdleWithPlayOnly() throws {
        for snapshot in [NowPlayingSnapshot(), NowPlayingSnapshot(title: "  ", artist: "Someone", isPlaying: true)] {
            let idle = try build(snapshot)
            #expect(idle.title == "Not Playing")
            #expect(idle.commands == [.play])
            #expect(idle.artist == nil && idle.artwork == nil && !idle.isPlaying)
        }
    }

    @Test func template_whenPlaying_thenCarriesTrackAndOffersPause() throws {
        let playing = try build(NowPlayingSnapshot(title: "Song", artist: "Artist", album: "Album", artwork: Data([1]), elapsed: 30, duration: 200, isPlaying: true))
        #expect(playing.id == NowPlayingProjection.rootTemplateID)
        #expect(playing.title == "Song" && playing.artist == "Artist" && playing.album == "Album")
        #expect(playing.artwork == Data([1]))
        #expect(playing.elapsed == 30 && playing.duration == 200 && playing.isPlaying)
        #expect(playing.commands == [.previousTrack, .pause, .nextTrack, .restartTrack])
    }

    @Test func template_whenPaused_thenOffersPlay() throws {
        #expect(try build(NowPlayingSnapshot(title: "Song", isPlaying: false)).commands.contains(.play))
    }

    @Test func template_whenTimesAreBroken_thenClamped() throws {
        #expect(try build(NowPlayingSnapshot(title: "S", elapsed: 500, duration: 200)).elapsed == 200)
        #expect(try build(NowPlayingSnapshot(title: "S", elapsed: -5, duration: 200)).elapsed == 0)
        #expect(try build(NowPlayingSnapshot(title: "S", elapsed: .nan, duration: .infinity)).duration == 0)
        #expect(try build(NowPlayingSnapshot(title: "S", elapsed: 42, duration: -1)).elapsed == 42)
    }

    @Test func template_whenArtworkOverCap_thenLeftOut() throws {
        let big = Data(count: ProjectionLimits.standard.maxArtworkBytes + 1)
        #expect(try build(NowPlayingSnapshot(title: "S", artwork: big)).artwork == nil)
    }

    @Test func template_whenTextTooLong_thenTruncated() throws {
        let long = String(repeating: "x", count: 300)
        let template = try build(NowPlayingSnapshot(title: long, artist: long, album: long))
        #expect(template.title.count == 80 && template.artist?.count == 80 && template.album?.count == 80)
    }

    @Test func elapsed_whenPlaying_thenAdvancesWithHubClockUpToDuration() {
        let template = NowPlayingTemplate(id: "n", title: "S", elapsed: 10, duration: 100, isPlaying: true)
        #expect(NowPlayingProjection.elapsed(for: template, receivedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(20)) == 30)
        #expect(NowPlayingProjection.elapsed(for: template, receivedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(500)) == 100)
        #expect(NowPlayingProjection.elapsed(for: template, receivedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(-5)) == 10)
    }

    @Test func elapsed_whenPausedOrDurationUnknown_thenDoesNotAdvanceOrClamp() {
        let paused = NowPlayingTemplate(id: "n", title: "S", elapsed: 10, duration: 100, isPlaying: false)
        #expect(NowPlayingProjection.elapsed(for: paused, receivedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(20)) == 10)
        let live = NowPlayingTemplate(id: "n", title: "S", elapsed: 10, duration: 0, isPlaying: true)
        #expect(NowPlayingProjection.elapsed(for: live, receivedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(20)) == 30)
    }
}
