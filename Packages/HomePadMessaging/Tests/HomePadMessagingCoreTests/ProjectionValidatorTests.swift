import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct ProjectionValidatorTests {
    let validator = ProjectionValidator()
    typealias Failure = ProjectionValidationError

    private func expect(_ template: ProjectionTemplate, fails error: Failure, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(throws: error, sourceLocation: sourceLocation) { try validator.validate(template) }
    }

    @Test(arguments: Fixture.allTemplates)
    func validateTemplate_whenWithinLimits_thenPasses(template: ProjectionTemplate) throws {
        try validator.validate(template)
    }

    @Test func templateAccessors_whenAnyCase_thenReportIdentityTitleAndKind() {
        #expect(Fixture.allTemplates.map(\.id) == ["root", "grid", "np", "info", "agenda"])
        #expect(Fixture.allTemplates.map(\.title) == ["List", "Grid", "Song", "Info", "Today"])
        #expect(Fixture.allTemplates.map(\.kind) == ProjectionTemplateKind.allCases)
    }

    // MARK: Apps

    @Test func validateApps_whenValid_thenPasses() throws {
        try validator.validate(apps: [Fixture.app("a"), Fixture.app("b")])
    }

    @Test func validateApps_whenTooMany_thenFails() {
        let apps = (0...12).map { Fixture.app("app\($0)") }
        #expect(throws: Failure.tooManyItems(field: "apps", limit: 12)) { try validator.validate(apps: apps) }
    }

    @Test func validateApps_whenDuplicateIDs_thenFails() {
        #expect(throws: Failure.duplicateIdentifier(field: "app.id")) { try validator.validate(apps: [Fixture.app("a"), Fixture.app("a")]) }
    }

    @Test func validateApp_whenIDIsEmptyOrHasWhitespaceOrIsTooLong_thenFails() {
        for id in ["", "has space", "line\nbreak", "bell\u{7}", String(repeating: "x", count: 129)] {
            #expect(throws: Failure.invalidIdentifier(field: "app.id")) { try validator.validate(Fixture.app(id)) }
        }
    }

    @Test func validateApp_whenNameIsBlankOrTooLong_thenFails() {
        var app = Fixture.app()
        app.name = "   "
        #expect(throws: Failure.emptyText(field: "app.name")) { try validator.validate(app) }
        app.name = String(repeating: "n", count: 81)
        #expect(throws: Failure.textTooLong(field: "app.name", limit: 80)) { try validator.validate(app) }
    }

    @Test func validateApp_whenSymbolNameIsNotASymbolName_thenFails() {
        for symbol in ["", "Has Caps", "emoji😀", String(repeating: "a", count: 65)] {
            var app = Fixture.app()
            app.symbolName = symbol
            #expect(throws: Failure.invalidSymbolName(field: "app.symbolName")) { try validator.validate(app) }
        }
    }

    // MARK: Shared template rules

    @Test func validateTemplate_whenIDInvalid_thenFails() {
        expect(Fixture.list(""), fails: .invalidIdentifier(field: "template.id"))
    }

    @Test func validateTemplate_whenTitleBlankOrTooLong_thenFails() {
        expect(Fixture.list(title: " "), fails: .emptyText(field: "template.title"))
        expect(Fixture.list(title: String(repeating: "t", count: 81)), fails: .textTooLong(field: "template.title", limit: 80))
    }

    // MARK: List

    @Test func validateList_whenTooManySections_thenFails() {
        let sections = (0..<9).map { ProjectionSection(id: "s\($0)", rows: []) }
        expect(.list(ListTemplate(id: "l", title: "L", sections: sections)), fails: .tooManyItems(field: "list.sections", limit: 8))
    }

    @Test func validateList_whenTooManyRowsAcrossSections_thenFails() {
        let sections = (0..<5).map { section in
            ProjectionSection(id: "s\(section)", rows: (0..<5).map { ProjectionRow(id: "r\(section).\($0)", title: "Row") })
        }
        expect(.list(ListTemplate(id: "l", title: "L", sections: sections)), fails: .tooManyItems(field: "list.rows", limit: 24))
    }

    @Test func validateList_whenDuplicateSectionOrRowIDs_thenFails() {
        let section = ProjectionSection(id: "s", rows: [])
        expect(.list(ListTemplate(id: "l", title: "L", sections: [section, section])), fails: .duplicateIdentifier(field: "section.id"))
        expect(Fixture.list(rows: [Fixture.row("a"), Fixture.row("a")]), fails: .duplicateIdentifier(field: "row.id"))
    }

    @Test func validateList_whenSectionFieldsInvalid_thenFails() {
        expect(.list(ListTemplate(id: "l", title: "L", sections: [ProjectionSection(id: " ", rows: [])])), fails: .invalidIdentifier(field: "section.id"))
        let longHeader = ProjectionSection(id: "s", header: String(repeating: "h", count: 81), rows: [])
        expect(.list(ListTemplate(id: "l", title: "L", sections: [longHeader])), fails: .textTooLong(field: "section.header", limit: 80))
        expect(
            .list(ListTemplate(id: "l", title: "L", sections: [], emptyMessage: String(repeating: "e", count: 161))),
            fails: .textTooLong(field: "list.emptyMessage", limit: 160)
        )
    }

    @Test func validateRow_whenFieldsInvalid_thenFails() {
        expect(Fixture.list(rows: [ProjectionRow(id: "", title: "T")]), fails: .invalidIdentifier(field: "row.id"))
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: "")]), fails: .emptyText(field: "row.title"))
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: String(repeating: "t", count: 81))]), fails: .textTooLong(field: "row.title", limit: 80))
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: "T", subtitle: String(repeating: "s", count: 161))]), fails: .textTooLong(field: "row.subtitle", limit: 160))
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: "T", symbolName: "Bad Symbol")]), fails: .invalidSymbolName(field: "row.symbolName"))
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: "T", actionID: "bad id")]), fails: .invalidIdentifier(field: "row.actionID"))
    }

    @Test func validateRow_whenAccessoryInvalid_thenFails() {
        expect(Fixture.list(rows: [ProjectionRow(id: "r", title: "T", accessory: .badge(count: -1))]), fails: .invalidCount(field: "row.badge"))
        expect(
            Fixture.list(rows: [ProjectionRow(id: "r", title: "T", accessory: .detail(String(repeating: "d", count: 81)))]),
            fails: .textTooLong(field: "row.detail", limit: 80)
        )
    }

    @Test func validateRow_whenAccessoryValid_thenPasses() throws {
        let rows = [
            ProjectionRow(id: "a", title: "T"),
            ProjectionRow(id: "b", title: "T", accessory: .toggle(isOn: true)),
            ProjectionRow(id: "c", title: "T", accessory: .badge(count: 3)),
            ProjectionRow(id: "d", title: "T", accessory: .detail("9:41")),
        ]
        try validator.validate(Fixture.list(rows: rows))
    }

    // MARK: Grid and buttons

    @Test func validateGrid_whenButtonsInvalid_thenFails() {
        func grid(_ buttons: [ProjectionButton]) -> ProjectionTemplate { .grid(GridTemplate(id: "g", title: "G", buttons: buttons)) }
        let button = ProjectionButton(id: "b", title: "B", actionID: "a")
        expect(grid((0..<9).map { ProjectionButton(id: "b\($0)", title: "B", actionID: "a") }), fails: .tooManyItems(field: "grid.buttons", limit: 8))
        expect(grid([button, button]), fails: .duplicateIdentifier(field: "button.id"))
        expect(grid([ProjectionButton(id: "", title: "B", actionID: "a")]), fails: .invalidIdentifier(field: "button.id"))
        expect(grid([ProjectionButton(id: "b", title: "", actionID: "a")]), fails: .emptyText(field: "button.title"))
        expect(grid([ProjectionButton(id: "b", title: "B", symbolName: "NO", actionID: "a")]), fails: .invalidSymbolName(field: "button.symbolName"))
        expect(grid([ProjectionButton(id: "b", title: "B", actionID: "")]), fails: .invalidIdentifier(field: "button.actionID"))
    }

    // MARK: Now playing

    @Test func validateNowPlaying_whenTextTooLong_thenFails() {
        let long = String(repeating: "a", count: 81)
        expect(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", artist: long)), fails: .textTooLong(field: "nowPlaying.artist", limit: 80))
        expect(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", album: long)), fails: .textTooLong(field: "nowPlaying.album", limit: 80))
    }

    @Test func validateNowPlaying_whenArtworkOverCap_thenFails() {
        let artwork = Data(count: 96 * 1024 + 1)
        expect(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", artwork: artwork)), fails: .artworkTooLarge(limit: 96 * 1024))
    }

    @Test func validateNowPlaying_whenArtworkAtCap_thenPasses() throws {
        try validator.validate(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", artwork: Data(count: 96 * 1024))))
    }

    @Test func validateNowPlaying_whenTimesInvalid_thenFails() {
        for (elapsed, duration) in [(-1.0, 10.0), (1.0, -10.0), (.nan, 10.0), (1.0, .infinity), (11.0, 10.0)] {
            expect(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", elapsed: elapsed, duration: duration)), fails: .invalidPlaybackTime)
        }
    }

    @Test func validateNowPlaying_whenDurationUnknown_thenElapsedMayExceedIt() throws {
        try validator.validate(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", elapsed: 30, duration: 0)))
    }

    @Test func validateNowPlaying_whenCommandsRepeat_thenFails() {
        expect(.nowPlaying(NowPlayingTemplate(id: "n", title: "T", commands: [.play, .play])), fails: .duplicateIdentifier(field: "nowPlaying.commands"))
    }

    // MARK: Information and agenda

    @Test func validateInformation_whenInvalid_thenFails() {
        func info(_ items: [InformationItem], buttons: [ProjectionButton] = []) -> ProjectionTemplate {
            .information(InformationTemplate(id: "i", title: "I", items: items, buttons: buttons))
        }
        let item = InformationItem(id: "i", label: "L", value: "V")
        expect(info((0..<13).map { InformationItem(id: "i\($0)", label: "L", value: "V") }), fails: .tooManyItems(field: "information.items", limit: 12))
        expect(info([item, item]), fails: .duplicateIdentifier(field: "information.item.id"))
        expect(info([InformationItem(id: "", label: "L", value: "V")]), fails: .invalidIdentifier(field: "information.item.id"))
        expect(info([InformationItem(id: "i", label: "", value: "V")]), fails: .emptyText(field: "information.label"))
        expect(info([InformationItem(id: "i", label: "L", value: String(repeating: "v", count: 161))]), fails: .textTooLong(field: "information.value", limit: 160))
        expect(
            info([item], buttons: (0..<4).map { ProjectionButton(id: "b\($0)", title: "B", actionID: "a") }),
            fails: .tooManyItems(field: "information.buttons", limit: 3)
        )
    }

    @Test func validateAgenda_whenInvalid_thenFails() {
        func agenda(_ entries: [AgendaEntry], empty: String? = nil) -> ProjectionTemplate {
            .agenda(AgendaTemplate(id: "a", title: "A", entries: entries, emptyMessage: empty))
        }
        let entry = AgendaEntry(id: "e", kind: .event, title: "E")
        expect(agenda((0..<25).map { AgendaEntry(id: "e\($0)", kind: .event, title: "E") }), fails: .tooManyItems(field: "agenda.entries", limit: 24))
        expect(agenda([entry, entry]), fails: .duplicateIdentifier(field: "agenda.entry.id"))
        expect(agenda([], empty: String(repeating: "e", count: 161)), fails: .textTooLong(field: "agenda.emptyMessage", limit: 160))
        expect(agenda([AgendaEntry(id: "", kind: .event, title: "E")]), fails: .invalidIdentifier(field: "agenda.entry.id"))
        expect(agenda([AgendaEntry(id: "e", kind: .event, title: "")]), fails: .emptyText(field: "agenda.title"))
        expect(agenda([AgendaEntry(id: "e", kind: .event, title: "E", detail: String(repeating: "d", count: 161))]), fails: .textTooLong(field: "agenda.detail", limit: 160))
        expect(agenda([AgendaEntry(id: "e", kind: .reminder, title: "E", actionID: "bad id")]), fails: .invalidIdentifier(field: "agenda.actionID"))
    }

    // MARK: Hub actions

    @Test func validateAction_whenValid_thenPasses() throws {
        try validator.validate(appID: "calendar")
        try validator.validate(actionID: "open.1", payload: ["value": "true"])
    }

    @Test func validateAction_whenInvalid_thenFails() {
        #expect(throws: Failure.invalidIdentifier(field: "appID")) { try validator.validate(appID: "") }
        #expect(throws: Failure.invalidIdentifier(field: "actionID")) { try validator.validate(actionID: "", payload: [:]) }
        let big = Dictionary(uniqueKeysWithValues: (0..<9).map { ("k\($0)", "v") })
        #expect(throws: Failure.tooManyItems(field: "action.payload", limit: 8)) { try validator.validate(actionID: "a", payload: big) }
        #expect(throws: Failure.invalidIdentifier(field: "action.payload.key")) { try validator.validate(actionID: "a", payload: ["bad key": "v"]) }
        #expect(throws: Failure.textTooLong(field: "action.payload.value", limit: 2000)) {
            try validator.validate(actionID: "a", payload: ["k": String(repeating: "v", count: 2001)])
        }
    }

    // MARK: Truncation

    @Test func projectionTruncated_whenLongerThanLimit_thenEndsWithEllipsisAtLimit() {
        #expect("abcdef".projectionTruncated(to: 4) == "abc\u{2026}")
        #expect("abcdef".projectionTruncated(to: 4).count == 4)
    }

    @Test func projectionTruncated_whenWithinLimitOrLimitIsZero_thenUnchangedOrEmpty() {
        #expect("abc".projectionTruncated(to: 3) == "abc")
        #expect("abc".projectionTruncated(to: 0) == "")
    }

    @Test func customLimits_whenLowered_thenAreEnforced() {
        var limits = ProjectionLimits()
        limits.maxTitleLength = 3
        #expect(throws: Failure.textTooLong(field: "template.title", limit: 3)) {
            try ProjectionValidator(limits: limits).validate(Fixture.list(title: "Long"))
        }
    }
}
