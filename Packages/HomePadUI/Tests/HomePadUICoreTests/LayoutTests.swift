import Foundation
import Testing
@testable import HomePadUICore

@Suite struct LayoutTests {
    private let owner = LayoutOwner.profile(UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID())

    @Test func storageKey_whenProfile_thenLowercasedIdentifier() {
        #expect(LayoutOwner.guest.storageKey == "guest")
        #expect(owner.storageKey == "11111111-2222-3333-4444-555555555555")
    }

    @Test func item_whenIdentifierRoundTrips_thenSameItem() {
        #expect(HomeScreenItem(id: "app.timers") == .app(.timers))
        #expect(HomeScreenItem(id: "widget.weather") == .widget(.weather))
        #expect(HomeScreenItem.app(.timers).id == "app.timers")
        #expect(HomeScreenItem.widget(.weather).id == "widget.weather")
        #expect(HomeScreenItem(id: "app.teleporter") == nil)
        #expect(HomeScreenItem(id: "widget.teleporter") == nil)
        #expect(HomeScreenItem(id: "gadget.timers") == nil)
        #expect(HomeScreenItem(id: "timers") == nil)
        #expect(HomeScreenItem.app(.projectedApps).access == .personal)
        #expect(HomeScreenItem.widget(.timers).access == .guest)
        #expect(HomeScreenItem.app(.clock).span == 1 && HomeScreenItem.widget(.clock).span == 2)
    }

    @Test func defaultLayout_whenGuest_thenHasNoMemberOrPersonalItems() {
        let guest = HomeScreenLayout.defaultLayout(for: .guest)
        #expect(!guest.items.contains(.app(.projectedApps)))
        #expect(!guest.items.contains(.widget(.nextAlarm)))
        #expect(!guest.items.contains(.app(.alarms)))
        #expect(guest.items.contains(.app(.timers)))
        #expect(guest.items.contains(.app(.people)))
        let member = HomeScreenLayout.defaultLayout(for: owner)
        #expect(member.items.contains(.app(.projectedApps)))
        #expect(Set(HubApp.allCases.map(HomeScreenItem.app)).isSubset(of: Set(member.items)))
        #expect(member.lastFace == nil)
    }

    @Test func sanitized_whenDuplicatesAndMissingApps_thenDedupesAndAppendsCatalog() {
        let layout = HomeScreenLayout(lastFace: .flow, items: [.app(.music), .app(.music), .widget(.timers)])
        let cleaned = layout.sanitized(for: owner)
        #expect(Array(cleaned.items.prefix(2)) == [.app(.music), .widget(.timers)])
        #expect(cleaned.items.filter { $0 == .app(.music) }.count == 1)
        #expect(cleaned.items.contains(.app(.settings)))
        #expect(cleaned.lastFace == .flow)
    }

    @Test func move_whenBothKnown_thenItemTakesTargetPosition() {
        var layout = HomeScreenLayout(items: [.app(.clock), .app(.timers), .app(.music), .app(.home)])
        layout.move(itemID: "app.home", onto: "app.timers")
        #expect(layout.items == [.app(.clock), .app(.home), .app(.timers), .app(.music)])
        layout.move(itemID: "app.clock", onto: "app.music")
        #expect(layout.items == [.app(.home), .app(.timers), .app(.music), .app(.clock)])
        let before = layout
        layout.move(itemID: "app.clock", onto: "app.clock")
        layout.move(itemID: "app.nope", onto: "app.clock")
        layout.move(itemID: "app.clock", onto: "app.nope")
        #expect(layout == before)
    }

    @Test func codec_whenRoundTripped_thenLayoutSurvives() throws {
        let layout = HomeScreenLayout(lastFace: .analog, items: [.app(.music), .widget(.weather)]).sanitized(for: owner)
        let data = try LayoutCodec.encode(layout)
        #expect(LayoutCodec.decode(data, owner: owner) == layout)
    }

    @Test func codec_whenVersionUnknown_thenFallsBackToDefault() {
        let future = Data(#"{"version":7,"payload":{"items":["app.music"],"lastFace":"flow"}}"#.utf8)
        #expect(LayoutCodec.decode(future, owner: owner) == .defaultLayout(for: owner))
        #expect(LayoutCodec.decode(Data("garbage".utf8), owner: .guest) == .defaultLayout(for: .guest))
        #expect(LayoutCodec.decode(nil, owner: .guest) == .defaultLayout(for: .guest))
    }

    @Test func codec_whenItemsOrFaceUnknown_thenDropsThemAndKeepsTheRest() {
        let data = Data(#"{"version":1,"payload":{"items":["app.music","app.hologram","widget.timers"],"lastFace":"hologram"}}"#.utf8)
        let layout = LayoutCodec.decode(data, owner: owner)
        #expect(Array(layout.items.prefix(2)) == [.app(.music), .widget(.timers)])
        #expect(layout.lastFace == nil)
        let noFace = Data(#"{"version":1,"payload":{"items":[]}}"#.utf8)
        #expect(LayoutCodec.decode(noFace, owner: owner).lastFace == nil)
    }

    @Test func codec_whenGuestFileHoldsPersonalItems_thenStripsThem() {
        let data = Data(#"{"version":1,"payload":{"items":["app.projectedApps","app.music"]}}"#.utf8)
        let layout = LayoutCodec.decode(data, owner: .guest)
        #expect(!layout.items.contains(.app(.projectedApps)))
        #expect(layout.items.first == .app(.music))
    }

    @Test func codec_whenFileHoldsAnAppAndWidgetThatWereRemoved_thenDropsThemAndKeepsTheRest() {
        // Messages was an app and a widget in earlier versions.
        let data = Data(#"{"version":1,"payload":{"items":["app.messages","app.music","widget.messages","widget.timers","app.timers"],"lastFace":"flow"}}"#.utf8)
        let layout = LayoutCodec.decode(data, owner: owner)
        #expect(Array(layout.items.prefix(3)) == [.app(.music), .widget(.timers), .app(.timers)])
        #expect(layout.lastFace == .flow)
        #expect(!layout.items.map(\.id).contains { $0.hasSuffix(".messages") })
        #expect(HomeScreenItem(id: "app.messages") == nil && HomeScreenItem(id: "widget.messages") == nil)
        // Saving it again writes only what this version knows.
        let saved = try? LayoutCodec.encode(layout)
        #expect(saved.map { String(decoding: $0, as: UTF8.self).contains("messages") } == false)
    }

    @Test func fileStore_whenSavedPerOwner_thenEachOwnerReadsTheirOwn() throws {
        let directory = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileLayoutStore(directory: directory)
        #expect(store.layout(for: owner) == .defaultLayout(for: owner))
        var mine = store.layout(for: owner)
        mine.lastFace = .fade
        mine.move(itemID: "app.settings", onto: "app.projectedApps")
        try store.save(mine, for: owner)
        var guest = store.layout(for: .guest)
        guest.lastFace = .rainbow
        try store.save(guest, for: .guest)
        #expect(store.layout(for: owner) == mine)
        #expect(store.layout(for: .guest).lastFace == .rainbow)
        try store.removeLayout(for: owner)
        try store.removeLayout(for: owner)
        #expect(store.layout(for: owner) == .defaultLayout(for: owner))
    }

    @Test func fileStore_whenDirectoryCannotBeWritten_thenThrowsUnwritable() throws {
        let directory = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let store = FileLayoutStore(directory: blocker)
        #expect(throws: SnapshotStoreError.unwritable) { try store.save(.defaultLayout(for: .guest), for: .guest) }
        #expect(store.layout(for: .guest) == .defaultLayout(for: .guest))
    }

    @Test func snapshotStore_whenPathIsADirectory_thenUnreadableAndRemoveFails() throws {
        let directory = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("state.json", isDirectory: true)
        try FileManager.default.createDirectory(at: nested.appendingPathComponent("child"), withIntermediateDirectories: true)
        let store = FileSnapshotStore(url: nested)
        #expect(throws: SnapshotStoreError.unreadable) { try store.load() }
        #expect(throws: SnapshotStoreError.unwritable) { try store.save(Data()) }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        #expect(throws: SnapshotStoreError.unwritable) { try store.remove() }
    }

    @Test func snapshotStore_whenFileAndMemory_thenLoadSaveRemove() throws {
        let directory = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FileSnapshotStore(url: directory.appendingPathComponent("nested/state.json"))
        #expect(try file.load() == nil)
        try file.save(Data("abc".utf8))
        #expect(try file.load() == Data("abc".utf8))
        try file.remove()
        #expect(try file.load() == nil)
        let memory = InMemorySnapshotStore(data: Data("1".utf8))
        #expect(try memory.load() == Data("1".utf8))
        try memory.save(Data("2".utf8))
        #expect(try memory.load() == Data("2".utf8))
        try memory.remove()
        #expect(try memory.load() == nil)
    }

    @Test func memoryStore_whenSavedAndRemoved_thenBehavesLikeFileStore() throws {
        let store = InMemoryLayoutStore()
        #expect(store.layout(for: .guest) == .defaultLayout(for: .guest))
        var layout = store.layout(for: owner)
        layout.lastFace = .calendar
        try store.save(layout, for: owner)
        #expect(store.layout(for: owner).lastFace == .calendar)
        try store.removeLayout(for: owner)
        #expect(store.layout(for: owner).lastFace == nil)
        let seeded = InMemoryLayoutStore(layouts: [.guest: HomeScreenLayout(items: [.app(.projectedApps), .app(.clock)])])
        #expect(seeded.layout(for: .guest).items.first == .app(.clock))
    }
}

@Suite struct HomeGridPackerTests {
    @Test func pack_whenWidgetsAndIcons_thenIconsFillBesideWidgets() {
        let items: [HomeScreenItem] = [.app(.photos), .app(.beam), .widget(.weather), .app(.home), .app(.music), .widget(.timers), .app(.timers)]
        let result = HomeGridPacker.pack(items, columns: 4)
        let positions = Dictionary(uniqueKeysWithValues: result.placements.map { ($0.id, [$0.column, $0.row, $0.span]) })
        #expect(positions["app.photos"] == [0, 0, 1])
        #expect(positions["app.beam"] == [1, 0, 1])
        #expect(positions["widget.weather"] == [2, 0, 2])
        #expect(positions["app.home"] == [0, 1, 1])
        #expect(positions["app.music"] == [1, 1, 1])
        #expect(positions["widget.timers"] == [0, 2, 2])
        #expect(positions["app.timers"] == [2, 2, 1])
        #expect(result.rowCount == 4)
    }

    @Test func pack_whenWidgetDoesNotFitAtRowEnd_thenWrapsAndLaterIconBackfills() {
        let result = HomeGridPacker.pack([.app(.clock), .app(.timers), .app(.music), .widget(.weather), .app(.home)], columns: 4)
        let weather = result.placements[3]
        let home = result.placements[4]
        #expect(weather.column == 0 && weather.row == 1)
        #expect(home.column == 3 && home.row == 0)
    }

    @Test func pack_whenWidgetFollowsOneIcon_thenWidgetKeepsToAnEdge() {
        let result = HomeGridPacker.pack([.app(.beam), .widget(.weather), .app(.home), .app(.music)], columns: 4)
        let positions = Dictionary(uniqueKeysWithValues: result.placements.map { ($0.id, $0.column * 10 + $0.row) })
        #expect(positions["widget.weather"] == 20)
        #expect(positions["app.home"] == 10)
        #expect(positions["app.music"] == 1)
    }

    @Test func pack_whenColumnsTooFew_thenUsesAtLeastTwo() {
        let result = HomeGridPacker.pack([.widget(.weather), .app(.clock)], columns: 1)
        #expect(result.placements[0].span == 2)
        #expect(result.placements[1].row == 2)
        #expect(HomeGridPacker.pack([], columns: 4) == HomeGridPacker.Result(placements: [], rowCount: 0))
    }
}
