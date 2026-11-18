import Foundation
import HomePadCore
import Testing
@testable import HomePadMessagingCore

private enum Context {
    /// Midnight UTC on Saturday, May 9, 2026.
    static let midnight = Date(timeIntervalSinceReferenceDate: 799_977_600)
    static let now = midnight.addingTimeInterval(12 * 3600)
    static let style = ProjectedContextTimeStyle(locale: Locale(identifier: "en_US"), timeZone: .gmt)

    static func hour(_ value: Double) -> Date {
        midnight.addingTimeInterval(value * 3600)
    }

    static func conversation(_ id: String, from title: String = "Carol", preview: String? = "Hi", at date: Date = now) -> ProjectedConversationSummary {
        ProjectedConversationSummary(id: id, title: title, preview: preview, lastMessageAt: date, unreadCount: 1, actionID: "messages.open.\(id)")
    }

    static func conversations(_ items: [ProjectedConversationSummary], id: String = "messages.list") -> ProjectionTemplate {
        .conversationList(ConversationListTemplate(id: id, title: "Messages", conversations: items, emptyMessage: "No messages"))
    }

    static func agenda(_ entries: [AgendaEntry], id: String = "agenda") -> ProjectionTemplate {
        .agenda(AgendaTemplate(id: id, title: "Agenda", entries: entries, emptyMessage: "Nothing"))
    }

    static func event(_ id: String, _ title: String = "Lunch", start: Date? = hour(15), end: Date? = hour(16), allDay: Bool = false, place: String? = "Cafe") -> AgendaEntry {
        AgendaEntry(id: id, kind: .event, title: title, start: start, end: end, isAllDay: allDay, detail: place)
    }

    static func reminder(_ id: String, _ title: String = "Milk", due: Date? = hour(18), allDay: Bool = false, list: String? = "Groceries", done: Bool = false) -> AgendaEntry {
        AgendaEntry(id: id, kind: .reminder, title: title, start: due, end: due, isAllDay: allDay, detail: list, isCompleted: done, actionID: "agenda.toggle.\(id)")
    }

    static func player(title: String = "Song", artist: String? = "Artist", album: String? = "Album", isPlaying: Bool = true) -> ProjectionTemplate {
        .nowPlaying(NowPlayingTemplate(id: "nowPlaying.root", title: title, artist: artist, album: album, elapsed: 10, duration: 100, isPlaying: isPlaying, commands: [.pause]))
    }

    static func source(_ templates: [ProjectionTemplate], app: String = "app", device: UUID = Fixture.phoneID, owner: UUID = Fixture.alice) -> ProjectedContextSource {
        ProjectedContextSource(entryID: ProjectedAppEntryID(deviceID: device, appID: app), ownerProfileID: owner, templates: templates)
    }

    static func summaries(_ sources: [ProjectedContextSource], limit: Int = 8, maxTextLength: Int = 140) -> [ProjectedContextSummary] {
        ProjectedContextSummarizer.summaries(from: sources, limit: limit, maxTextLength: maxTextLength, now: now, timeStyle: style)
    }

    static func summaries(_ templates: ProjectionTemplate..., limit: Int = 8, maxTextLength: Int = 140) -> [ProjectedContextSummary] {
        summaries([source(templates)], limit: limit, maxTextLength: maxTextLength)
    }
}

@Suite struct ProjectedContextSummarizerTests {
    // MARK: Nothing to say

    @Test func summaries_whenThereAreNoSourcesOrTemplates_thenEmpty() {
        #expect(Context.summaries([]).isEmpty)
        #expect(Context.summaries([Context.source([])]).isEmpty)
    }

    @Test func summaries_whenTemplatesHoldNoItems_thenEmpty() {
        #expect(Context.summaries(Context.conversations([]), Context.agenda([])).isEmpty)
    }

    @Test func summaries_whenTemplateKindSaysNothingAboutItsContent_thenEmpty() {
        let silent = Fixture.allTemplates.filter { [.list, .grid, .information, .conversation].contains($0.kind) }
        #expect(silent.count == 4)
        #expect(Context.summaries([Context.source(silent)]).isEmpty)
    }

    @Test func summaries_whenLimitOrLengthIsNotPositive_thenEmpty() {
        let template = Context.conversations([Context.conversation("c1")])
        #expect(Context.summaries(template, limit: 0).isEmpty)
        #expect(Context.summaries(template, limit: -1).isEmpty)
        #expect(Context.summaries(template, maxTextLength: 0).isEmpty)
        #expect(Context.summaries(template, maxTextLength: -5).isEmpty)
    }

    // MARK: Messages

    @Test func summaries_whenConversationListHasPreviews_thenMessagesNewestFirst() {
        let result = Context.summaries(Context.conversations([
            Context.conversation("old", from: "Carol", preview: "See you at 5", at: Context.hour(9)),
            Context.conversation("new", from: "Dave", preview: "Running late", at: Context.hour(11)),
        ]))
        #expect(result == [
            ProjectedContextSummary(id: "\(Fixture.phoneID.uuidString)/app/message/new", kind: .message, ownerProfileID: Fixture.alice, title: "Dave", detail: "Running late"),
            ProjectedContextSummary(id: "\(Fixture.phoneID.uuidString)/app/message/old", kind: .message, ownerProfileID: Fixture.alice, title: "Carol", detail: "See you at 5"),
        ])
    }

    @Test func summaries_whenConversationsShareATime_thenOrderIsStable() {
        let first = Context.summaries(Context.conversations([Context.conversation("b"), Context.conversation("a", from: "Dave")]))
        let second = Context.summaries(Context.conversations([Context.conversation("a", from: "Dave"), Context.conversation("b")]))
        #expect(first == second)
        #expect(first.map(\.title) == ["Dave", "Carol"])
    }

    @Test func summaries_whenOwnerShowsSenderOnly_thenNoMessageText() {
        let result = Context.summaries(Context.conversations([Context.conversation("c1", from: "Carol", preview: nil)]))
        #expect(result.map(\.title) == ["Carol"])
        #expect(result.map(\.detail) == [""])
    }

    @Test func summaries_whenAConversationIsOpenOnTheHub_thenItsBubblesAreNotRead() {
        let open = ProjectionTemplate.conversation(ConversationTemplate(id: "open", title: "Carol", conversationID: "c1", bubbles: [
            ProjectedBubble(id: "m1", text: "the full secret text", isFromMe: false, sentAt: Context.now),
        ], canReply: true))
        let result = Context.summaries(Context.conversations([Context.conversation("c1", preview: nil)]), open)
        #expect(result.count == 1)
        #expect(!result.contains { $0.detail.contains("secret") || $0.title.contains("secret") })
    }

    // MARK: Events and reminders

    @Test func summaries_whenAgendaMixesKinds_thenEachEntryKeepsItsKind() {
        let result = Context.summaries(Context.agenda([Context.event("e1"), Context.reminder("r1")]))
        #expect(result.map(\.kind) == [.calendarEvent, .reminder])
        #expect(result.map(\.title) == ["Lunch", "Milk"])
        #expect(result.map(\.id) == ["\(Fixture.phoneID.uuidString)/app/calendarEvent/e1", "\(Fixture.phoneID.uuidString)/app/reminder/r1"])
        #expect(result.allSatisfy { $0.ownerProfileID == Fixture.alice })
    }

    @Test func summaries_whenEventsAreOutOfOrder_thenSoonestFirstAndUndatedLast() {
        let result = Context.summaries(Context.agenda([
            Context.event("none", "Sometime", start: nil, end: nil),
            Context.event("late", "Dinner", start: Context.hour(19), end: Context.hour(20)),
            Context.event("soon", "Lunch", start: Context.hour(13), end: Context.hour(14)),
        ]))
        #expect(result.map(\.title) == ["Lunch", "Dinner", "Sometime"])
    }

    @Test func summaries_whenEventHasEnded_thenLeftOutButOneInProgressStays() {
        let result = Context.summaries(Context.agenda([
            Context.event("ended", "Breakfast", start: Context.hour(8), end: Context.hour(9)),
            Context.event("justEnded", "Standup", start: Context.hour(11), end: Context.now),
            Context.event("running", "Workshop", start: Context.hour(11), end: Context.hour(13)),
            Context.event("open", "No End", start: Context.hour(10), end: nil),
        ]))
        #expect(result.map(\.title) == ["No End", "Workshop"])
    }

    @Test func summaries_whenReminderIsCompleted_thenLeftOutButAnOverdueOneComesFirst() {
        let result = Context.summaries(Context.agenda([
            Context.reminder("done", "Done", due: Context.hour(13), done: true),
            Context.reminder("later", "Later", due: Context.hour(20)),
            Context.reminder("overdue", "Overdue", due: Context.hour(-30)),
        ]))
        #expect(result.map(\.title) == ["Overdue", "Later"])
        #expect(result.allSatisfy { $0.kind == .reminder })
    }

    @Test func summaries_whenEventHasStartAndEnd_thenDetailIsTheIntervalAndThePlace() throws {
        let detail = try #require(Context.summaries(Context.agenda([Context.event("e1")])).first?.detail)
        for part in ["Sat", "May 9", "3:00", "4:00", "PM"] {
            #expect(detail.contains(part), "missing \(part)")
        }
        #expect(detail.hasSuffix(", Cafe"))
        #expect(!detail.contains { $0.isWhitespace && $0 != " " })
    }

    @Test func summaries_whenEventHasNoUsableEnd_thenDetailIsTheStart() throws {
        let entries = [Context.event("e1", end: nil, place: nil), Context.event("e2", "Other", end: Context.hour(15), place: nil)]
        let details = Context.summaries(Context.agenda(entries)).map(\.detail)
        #expect(details.count == 2)
        for detail in details {
            #expect(detail.contains("May 9") && detail.contains("3:00"))
            #expect(!detail.contains("4:00"))
        }
    }

    @Test func summaries_whenEntryIsAllDay_thenDetailHasTheDayWithoutATime() throws {
        let result = Context.summaries(Context.agenda([
            Context.event("e1", "Holiday", start: Context.midnight.addingTimeInterval(86_400), end: Context.midnight.addingTimeInterval(2 * 86_400), allDay: true, place: nil),
            Context.reminder("r1", "Pay Rent", due: Context.midnight.addingTimeInterval(86_400), allDay: true, list: nil),
        ]))
        #expect(result.count == 2)
        for summary in result {
            #expect(summary.detail.contains("Sun") && summary.detail.contains("May 10"))
            #expect(!summary.detail.contains(":"))
        }
    }

    @Test func summaries_whenReminderHasADueTime_thenDetailIsTheTimeAndTheList() throws {
        let detail = try #require(Context.summaries(Context.agenda([Context.reminder("r1")])).first?.detail)
        #expect(detail.contains("May 9") && detail.contains("6:00"))
        #expect(detail.hasSuffix(", Groceries"))
    }

    @Test func summaries_whenEntryHasNoDate_thenDetailIsOnlyWhatIsLeft() {
        let result = Context.summaries(Context.agenda([
            Context.reminder("r1", "Listed", due: nil, list: "Groceries"),
            Context.reminder("r2", "Bare", due: nil, list: nil),
            Context.reminder("r3", "Blank", due: nil, list: "  \n "),
        ]))
        #expect(Dictionary(uniqueKeysWithValues: result.map { ($0.title, $0.detail) }) == ["Listed": "Groceries", "Bare": "", "Blank": ""])
    }

    // MARK: Now playing

    @Test func summaries_whenPlayerIsPlaying_thenTrackWithArtistAndAlbum() {
        #expect(Context.summaries([Context.source([Context.player()], app: "nowPlaying")]) == [
            ProjectedContextSummary(
                id: "\(Fixture.phoneID.uuidString)/nowPlaying/nowPlaying/nowPlaying.root",
                kind: .nowPlaying,
                ownerProfileID: Fixture.alice,
                title: "Song",
                detail: "Artist, Album"
            ),
        ])
        #expect(Context.summaries(Context.player(artist: nil, album: "Album")).map(\.detail) == ["Album"])
        #expect(Context.summaries(Context.player(artist: nil, album: nil)).map(\.detail) == [""])
    }

    @Test func summaries_whenPlayerIsPausedOrIdle_thenNothing() {
        #expect(Context.summaries(Context.player(isPlaying: false)).isEmpty)
        let idle = NowPlayingProjection.template(snapshot: NowPlayingSnapshot(), idleTitle: "Not Playing")
        #expect(Context.summaries(idle).isEmpty)
    }

    // MARK: Limit

    @Test func summaries_whenLimitIsSmallerThanTheContent_thenKindsTakeTurns() {
        let sources = [
            Context.source([Context.conversations((1...5).map { Context.conversation("c\($0)", from: "Sender \($0)", preview: "Text \($0)", at: Context.hour(Double(12 - $0))) })], app: "messages"),
            Context.source([Context.agenda((1...5).map { Context.event("e\($0)", "Event \($0)", start: Context.hour(Double(12 + $0)), end: Context.hour(Double(13 + $0))) })], app: "calendar"),
            Context.source([Context.agenda((1...2).map { Context.reminder("r\($0)", "Reminder \($0)", due: Context.hour(Double(12 + $0))) })], app: "reminders"),
            Context.source([Context.player()], app: "nowPlaying"),
        ]
        #expect(Context.summaries(sources, limit: 8).map(\.title) == [
            "Sender 1", "Event 1", "Reminder 1", "Song",
            "Sender 2", "Event 2", "Reminder 2",
            "Sender 3",
        ])
        #expect(Context.summaries(sources, limit: 3).map(\.kind) == [.message, .calendarEvent, .reminder])
        #expect(Context.summaries(sources, limit: 1).map(\.title) == ["Sender 1"])
        #expect(Context.summaries(sources, limit: 100).count == 13)
    }

    // MARK: Clipping

    @Test func summaries_whenTextIsLongerThanTheLength_thenClippedWithAnEllipsis() {
        let long = String(repeating: "abcdefghij", count: 30)
        let result = Context.summaries(Context.conversations([Context.conversation("c1", from: long, preview: long)]), maxTextLength: 40)
        #expect(result.map(\.title.count) == [40])
        #expect(result.map(\.detail.count) == [40])
        #expect(result.first?.detail == String(long.prefix(39)) + "\u{2026}")
        #expect(result.first?.title.hasSuffix("\u{2026}") == true)
    }

    @Test func summaries_whenTextFitsExactly_thenUnchanged() {
        let result = Context.summaries(Context.conversations([Context.conversation("c1", from: "Carol", preview: "12345")]), maxTextLength: 5)
        #expect(result.map(\.title) == ["Carol"])
        #expect(result.map(\.detail) == ["12345"])
    }

    @Test func summaries_whenTheCutFallsInsideAGrapheme_thenTheGraphemeIsKeptWholeOrDropped() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let flag = "\u{1F1FA}\u{1F1F8}"
        let accented = "e\u{0301}"
        let text = family + flag + accented + family + flag + accented
        #expect(text.count == 6)
        for length in 1...6 {
            let detail = Context.summaries(Context.conversations([Context.conversation("c1", preview: text)]), maxTextLength: length).first?.detail ?? ""
            let expected = length == 6 ? text : String(text.prefix(length - 1)) + "\u{2026}"
            #expect(detail == expected)
            #expect(detail.count == length)
            #expect(Array(detail).dropLast(length == 6 ? 0 : 1).allSatisfy { [family, flag, accented].contains(String($0)) })
        }
    }

    @Test func summaries_whenTextHasLineBreaksAndRuns_thenFoldedOntoOneLineBeforeCounting() {
        let result = Context.summaries(Context.conversations([Context.conversation("c1", from: " Carol\tSmith ", preview: "one\n\ntwo   three\u{202F}four\r\n")]), maxTextLength: 18)
        #expect(result.map(\.title) == ["Carol Smith"])
        #expect(result.map(\.detail) == ["one two three four"])
    }

    @Test func summaries_whenTitleIsBlank_thenLeftOut() {
        let result = Context.summaries(Context.conversations([Context.conversation("c1", from: " \n ", preview: "Hi"), Context.conversation("c2", from: "Dave")]))
        #expect(result.map(\.title) == ["Dave"])
    }

    // MARK: Identity

    @Test func summaries_whenTheSameItemChangesItsText_thenIDStaysTheSame() {
        let before = Context.summaries(Context.conversations([Context.conversation("c1", preview: "First", at: Context.hour(9))]), Context.agenda([Context.event("e1", "Lunch")]))
        let after = Context.summaries(Context.conversations([Context.conversation("c1", preview: "Second", at: Context.hour(10))]), Context.agenda([Context.event("e1", "Late Lunch")]))
        #expect(before.map(\.id) == after.map(\.id))
        #expect(before != after)
        #expect(Set(before.map(\.id)).count == 2)
        #expect(!before.contains { $0.id.contains("Carol") || $0.id.contains("First") || $0.id.contains("Lunch") })
    }

    @Test func summaries_whenAnItemShowsOnTwoScreens_thenListedOnce() {
        let result = Context.summaries(
            Context.agenda([Context.event("e1", "Lunch")], id: "root"),
            Context.agenda([Context.event("e1", "Lunch Again")], id: "detail")
        )
        #expect(result.map(\.title) == ["Lunch"])
    }

    @Test func summaries_whenTwoCompanionsProjectTheSameContent_thenListedOnceWithDistinctItemsKept() {
        let result = Context.summaries([
            Context.source([Context.agenda([Context.event("e1", "Lunch"), Context.event("e2", "Dinner", start: Context.hour(19), end: Context.hour(20))])], app: "calendar"),
            Context.source([Context.agenda([Context.event("x1", "Lunch"), Context.reminder("x2", "Lunch")])], app: "calendar", device: Fixture.otherPhoneID),
        ])
        #expect(result.map(\.title) == ["Lunch", "Lunch", "Dinner"])
        #expect(result.map(\.kind) == [.calendarEvent, .reminder, .calendarEvent])
        #expect(result.first?.id.hasPrefix(Fixture.phoneID.uuidString) == true)
    }

    @Test func timeStyle_whenCurrent_thenFollowsTheDevice() {
        #expect(ProjectedContextTimeStyle.current == ProjectedContextTimeStyle(locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent))
    }
}

/// Who gets summaries at all. The decision is `ProjectionClientState.contextSummaries`, which the
/// hub's `ProjectionClient` calls with the session's viewer.
@Suite struct ProjectedContextGateTests {
    private static let apps = [
        Fixture.app("messages"),
        Fixture.app("calendar"),
        Fixture.app("nowPlaying", personal: false),
    ]

    private func projecting(from device: PeerDevice = Fixture.phone, into state: inout ProjectionClientState, sender: String = "Carol", session: UUID = Fixture.hostSession) throws {
        try state.apply(Fixture.hostFrame(.announce(Self.apps), sequence: 1, session: session), from: device, now: Fixture.t0)
        let roots: [(String, ProjectionTemplate)] = [
            ("messages", Context.conversations([Context.conversation("c1", from: sender, preview: "Hi from \(sender)")])),
            ("calendar", Context.agenda([Context.event("e1", "Lunch with \(sender)")])),
            ("nowPlaying", Context.player(title: "Song for \(sender)")),
        ]
        for (offset, root) in roots.enumerated() {
            try state.apply(Fixture.hostFrame(.setRoot(appID: root.0, template: root.1), sequence: UInt64(offset + 2), session: session), from: device, now: Fixture.t0)
        }
    }

    private func alicesPhone() throws -> ProjectionClientState {
        var state = ProjectionClientState(session: Fixture.hubSession)
        try projecting(into: &state)
        return state
    }

    private func summaries(_ state: ProjectionClientState, viewer: ViewerContext, limit: Int = 8, maxTextLength: Int = 140) -> [ProjectedContextSummary] {
        state.contextSummaries(viewer: viewer, limit: limit, maxTextLength: maxTextLength, now: Context.now, timeStyle: Context.style)
    }

    @Test func contextSummaries_whenOwnerIsVerified_thenEveryKindFromTheirCompanion() throws {
        let result = summaries(try alicesPhone(), viewer: Fixture.aliceVerified)
        #expect(result.map(\.kind) == [.message, .calendarEvent, .nowPlaying])
        #expect(result.map(\.title) == ["Carol", "Lunch with Carol", "Song for Carol"])
        #expect(result.allSatisfy { $0.ownerProfileID == Fixture.alice && $0.id.hasPrefix(Fixture.phoneID.uuidString) })
    }

    @Test func contextSummaries_whenOwnerIsSelectedByHand_thenEmpty() throws {
        #expect(summaries(try alicesPhone(), viewer: Fixture.aliceManual).isEmpty)
    }

    @Test func contextSummaries_whenNobodyOrAGuestIsPresent_thenEmpty() throws {
        let state = try alicesPhone()
        #expect(summaries(state, viewer: .nobody).isEmpty)
        #expect(summaries(state, viewer: ViewerContext(activeProfileID: nil, isPersonalContentUnlocked: true)).isEmpty)
    }

    @Test func contextSummaries_whenAnotherMemberIsVerified_thenEmptyEvenForSharedApps() throws {
        #expect(summaries(try alicesPhone(), viewer: Fixture.bobVerified).isEmpty)
    }

    @Test func contextSummaries_whenTwoCompanionsProject_thenOnlyTheActiveMembersOwn() throws {
        var state = try alicesPhone()
        try projecting(from: Fixture.otherPhone, into: &state, sender: "Erin", session: UUID())
        #expect(summaries(state, viewer: Fixture.aliceVerified).map(\.title) == ["Carol", "Lunch with Carol", "Song for Carol"])
        let bobs = summaries(state, viewer: Fixture.bobVerified)
        #expect(bobs.map(\.title) == ["Erin", "Lunch with Erin", "Song for Erin"])
        #expect(bobs.allSatisfy { $0.ownerProfileID == Fixture.bob && $0.id.hasPrefix(Fixture.otherPhoneID.uuidString) })
        #expect(summaries(state, viewer: Fixture.aliceManual).isEmpty)
        #expect(summaries(state, viewer: .nobody).isEmpty)
    }

    @Test func contextSummaries_whenCompanionHasNoOwner_thenEmpty() throws {
        var state = ProjectionClientState(session: Fixture.hubSession)
        try projecting(from: PeerDevice(id: Fixture.phoneID, name: "Spare iPhone", role: .companion, profileID: nil), into: &state)
        #expect(summaries(state, viewer: Fixture.aliceVerified).isEmpty)
    }

    @Test func contextSummaries_whenCompanionIsReassigned_thenSummariesFollowTheNewOwner() throws {
        var state = try alicesPhone()
        let reassigned = PeerDevice(id: Fixture.phoneID, name: "Alice's iPhone", role: .companion, profileID: Fixture.bob)
        #expect(state.reconcile(connected: [reassigned], now: Fixture.t0).isEmpty)
        #expect(summaries(state, viewer: Fixture.aliceVerified).isEmpty)
        #expect(summaries(state, viewer: Fixture.bobVerified).allSatisfy { $0.ownerProfileID == Fixture.bob })
        #expect(summaries(state, viewer: Fixture.bobVerified).count == 3)
    }

    @Test func contextSummaries_whenMemberHasNoConnectedCompanion_thenEmpty() throws {
        #expect(summaries(ProjectionClientState(session: Fixture.hubSession), viewer: Fixture.aliceVerified).isEmpty)
        var state = try alicesPhone()
        state.deviceDisconnected(Fixture.phoneID)
        #expect(summaries(state, viewer: Fixture.aliceVerified).isEmpty)
    }

    @Test func contextSummaries_whenAnAppIsWithdrawn_thenItsContentIsGone() throws {
        var state = try alicesPhone()
        try state.apply(Fixture.hostFrame(.withdraw(appID: "messages"), sequence: 10), from: Fixture.phone, now: Fixture.t0)
        #expect(summaries(state, viewer: Fixture.aliceVerified).map(\.kind) == [.calendarEvent, .nowPlaying])
        try state.apply(Fixture.hostFrame(.announce([]), sequence: 11), from: Fixture.phone, now: Fixture.t0)
        #expect(summaries(state, viewer: Fixture.aliceVerified).isEmpty)
    }

    @Test func contextSummaries_whenAnAppHasNoRootYet_thenOnlyTheOthers() throws {
        var state = ProjectionClientState(session: Fixture.hubSession)
        try state.apply(Fixture.hostFrame(.announce(Self.apps), sequence: 1), from: Fixture.phone, now: Fixture.t0)
        #expect(summaries(state, viewer: Fixture.aliceVerified).isEmpty)
        try state.apply(Fixture.hostFrame(.setRoot(appID: "nowPlaying", template: Context.player()), sequence: 2), from: Fixture.phone, now: Fixture.t0)
        #expect(summaries(state, viewer: Fixture.aliceVerified).map(\.kind) == [.nowPlaying])
    }

    @Test func contextSummaries_whenAConversationIsPushed_thenEveryScreenOfTheStackIsRead() throws {
        var state = try alicesPhone()
        let more = Context.agenda([Context.event("e2", "Dinner", start: Context.hour(19), end: Context.hour(20))], id: "more")
        try state.apply(Fixture.hostFrame(.push(appID: "calendar", template: more), sequence: 10), from: Fixture.phone, now: Fixture.t0)
        #expect(summaries(state, viewer: Fixture.aliceVerified).filter { $0.kind == .calendarEvent }.map(\.title) == ["Lunch with Carol", "Dinner"])
    }

    @Test func contextSummaries_whenLimitAndLengthAreGiven_thenBothApply() throws {
        let result = summaries(try alicesPhone(), viewer: Fixture.aliceVerified, limit: 2, maxTextLength: 6)
        #expect(result.map(\.title) == ["Carol", "Lunch\u{2026}"])
        #expect(summaries(try alicesPhone(), viewer: Fixture.aliceVerified, limit: 0).isEmpty)
    }

    @Test func showsPersonalContent_whenViewerVaries_thenOnlyTheVerifiedOwnerPasses() {
        #expect(ProjectionVisibilityPolicy.showsPersonalContent(ownerProfileID: Fixture.alice, viewer: Fixture.aliceVerified))
        let refused: [ViewerContext] = [Fixture.aliceManual, Fixture.bobVerified, .nobody, ViewerContext(activeProfileID: nil, isPersonalContentUnlocked: true)]
        for viewer in refused {
            #expect(!ProjectionVisibilityPolicy.showsPersonalContent(ownerProfileID: Fixture.alice, viewer: viewer))
        }
        #expect(!ProjectionVisibilityPolicy.showsPersonalContent(ownerProfileID: nil, viewer: Fixture.aliceVerified))
    }
}
