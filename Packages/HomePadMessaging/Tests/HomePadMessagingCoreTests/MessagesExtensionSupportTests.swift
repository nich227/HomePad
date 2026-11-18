import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct MessagesExtensionStoreTests {
    private let suiteName = "HomePadMessagingCoreTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let store: MessagesExtensionStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = MessagesExtensionStore(defaults: defaults)
    }

    private func page(_ path: String, at offset: TimeInterval = 0) -> RecentPage {
        RecentPage(url: URL(string: "https://example.com/\(path)")!, title: path, beamedAt: Fixture.t0.addingTimeInterval(offset))
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func recentPages_whenNothingStored_thenEmptyAndSuggestionsDefaultOn() {
        defer { cleanUp() }
        #expect(store.recentPages().isEmpty)
        #expect(store.suggestsRecentPages)
    }

    @Test func record_whenPagesAdded_thenNewestFirstWithoutDuplicates() {
        defer { cleanUp() }
        store.record(page("a", at: 0))
        store.record(page("b", at: 10))
        store.record(page("a", at: 20))
        #expect(store.recentPages().map(\.title) == ["a", "b"])
        #expect(store.recentPages().first?.beamedAt == Fixture.t0.addingTimeInterval(20))
        #expect(store.recentPages().first?.id == "https://example.com/a")
    }

    @Test func record_whenMoreThanCap_thenOldestFallOff() {
        defer { cleanUp() }
        for index in 0..<10 {
            store.record(page("p\(index)", at: Double(index)))
        }
        #expect(store.recentPages().count == 8)
        #expect(store.recentPages().first?.title == "p9")
        #expect(store.recentPages().last?.title == "p2")
    }

    @Test func record_whenPageIsNotHTTP_thenIgnored() {
        defer { cleanUp() }
        store.record(RecentPage(url: URL(string: "file:///private/secret")!, title: nil, beamedAt: Fixture.t0))
        #expect(store.recentPages().isEmpty)
    }

    @Test func record_whenSuggestionsAreOff_thenNothingIsStoredAndExistingListIsCleared() {
        defer { cleanUp() }
        store.record(page("a"))
        defaults.set(false, forKey: MessagingSettings.suggestRecentPages.name)
        #expect(!store.suggestsRecentPages)
        #expect(store.recentPages().isEmpty)
        store.record(page("b"))
        #expect(defaults.data(forKey: MessagesExtensionStore.recentPagesKey) == nil)
        defaults.set(true, forKey: MessagingSettings.suggestRecentPages.name)
        #expect(store.recentPages().isEmpty)
    }

    @Test func recentPages_whenStoredDataIsCorruptOrHasBadURLs_thenThoseAreSkipped() throws {
        defer { cleanUp() }
        defaults.set(Data("garbage".utf8), forKey: MessagesExtensionStore.recentPagesKey)
        #expect(store.recentPages().isEmpty)
        let mixed = [page("ok"), RecentPage(url: URL(string: "ftp://example.com/x")!, title: nil, beamedAt: Fixture.t0)]
        defaults.set(try JSONEncoder().encode(mixed), forKey: MessagesExtensionStore.recentPagesKey)
        #expect(store.recentPages().map(\.title) == ["ok"])
    }

    @Test func hubItem_whenFresh_thenReturnedAndWhenStaleOrClearedThenNil() throws {
        defer { cleanUp() }
        #expect(store.hubItem(now: Fixture.t0) == nil)
        let link = try MessageDeepLinkCodec.appURL(for: .openApp(id: "messages"))
        let item = SharedHubItem(title: "Messages", link: link, updatedAt: Fixture.t0)
        store.setHubItem(item)
        #expect(store.hubItem(now: Fixture.t0.addingTimeInterval(599)) == item)
        #expect(store.hubItem(now: Fixture.t0.addingTimeInterval(600)) == nil)
        store.setHubItem(nil)
        #expect(store.hubItem(now: Fixture.t0) == nil)
    }

    @Test func hubItem_whenLinkIsNotAValidMessageLinkOrDataIsCorrupt_thenNil() throws {
        defer { cleanUp() }
        store.setHubItem(SharedHubItem(title: "Pair", link: URL(string: "homepad://message?v=1&kind=pair")!, updatedAt: Fixture.t0))
        #expect(store.hubItem(now: Fixture.t0) == nil)
        defaults.set(Data("garbage".utf8), forKey: MessagesExtensionStore.hubItemKey)
        #expect(store.hubItem(now: Fixture.t0) == nil)
    }
}

@Suite struct MessagesExtensionLogicTests {
    private let page = URL(string: "https://example.com/soup")!

    @Test func card_whenPageHasTitle_thenTitleIsCaptionAndHostIsSubcaption() throws {
        let card = try MessagesExtensionLogic.card(for: .beamPage(page), title: " Tomato Soup ")
        #expect(card.caption == "Tomato Soup")
        #expect(card.subcaption == "example.com")
        #expect(card.symbolName == "globe")
        #expect(try MessageDeepLinkCodec.decode(card.messageURL) == .beamPage(page))
    }

    @Test func card_whenPageHasNoTitle_thenHostIsCaption() throws {
        for title in [nil, "", "   "] as [String?] {
            let card = try MessagesExtensionLogic.card(for: .beamPage(page), title: title)
            #expect(card.caption == "example.com")
            #expect(card.subcaption == nil)
        }
    }

    @Test func card_whenTitleIsLong_thenTruncated() throws {
        let card = try MessagesExtensionLogic.card(for: .beamPage(page), title: String(repeating: "t", count: 200))
        #expect(card.caption.count == 80)
    }

    @Test func card_whenAppOrFace_thenUsesTitleOrFallsBackToID() throws {
        let app = try MessagesExtensionLogic.card(for: .openApp(id: "messages"), title: "Messages")
        #expect(app.caption == "Messages" && app.subcaption == nil && app.symbolName == "square.grid.2x2")
        let face = try MessagesExtensionLogic.card(for: .openFace(id: "analog"), title: nil)
        #expect(face.caption == "analog" && face.symbolName == "clock")
        #expect(try MessagesExtensionLogic.card(for: .openApp(id: "calendar"), title: nil).caption == "calendar")
        #expect(try MessagesExtensionLogic.card(for: .openFace(id: "analog"), title: "Analog").caption == "Analog")
    }

    @Test func card_whenLinkInvalid_thenThrows() {
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try MessagesExtensionLogic.card(for: .beamPage(URL(string: "file:///x")!), title: nil) }
    }

    @Test func pageURL_whenTextIsAWebAddress_thenParsed() {
        #expect(MessagesExtensionLogic.pageURL(fromText: " https://example.com/a ")?.absoluteString == "https://example.com/a")
        #expect(MessagesExtensionLogic.pageURL(fromText: "example.com/a")?.absoluteString == "https://example.com/a")
    }

    @Test func pageURL_whenTextIsNotAWebAddress_thenNil() {
        for text in [nil, "", "   ", "two words", "hello", "ftp://example.com", "javascript:alert(1)", "file:///etc/passwd"] as [String?] {
            #expect(MessagesExtensionLogic.pageURL(fromText: text) == nil)
        }
    }

    @Test func openAction_whenMessageCarriesAValidLink_thenOffersTheAppURL() throws {
        let messageURL = try MessageDeepLinkCodec.messageURL(for: .beamPage(page))
        let action = try #require(MessagesExtensionLogic.openAction(forMessageURL: messageURL))
        #expect(action.link == .beamPage(page))
        #expect(action.appURL == (try MessageDeepLinkCodec.appURL(for: .beamPage(page))))
    }

    @Test func openAction_whenMessageHasNoURLOrAForeignOne_thenNil() {
        #expect(MessagesExtensionLogic.openAction(forMessageURL: nil) == nil)
        #expect(MessagesExtensionLogic.openAction(forMessageURL: URL(string: "https://example.com")) == nil)
        #expect(MessagesExtensionLogic.openAction(forMessageURL: URL(string: "data:application/vnd.homepad.link,v=1&kind=pair")) == nil)
    }
}

@Suite struct IntentOutcomeTests {
    @Test func wasDelivered_whenDelivered_thenTrueOtherwiseFalse() {
        #expect(HubCommandOutcome.delivered(hubCount: 2).wasDelivered)
        for outcome in [HubCommandOutcome.noHubReachable, .rejected, .unavailable] {
            #expect(!outcome.wasDelivered)
        }
    }

    @Test func shouldKeepWaiting_whenInsideLimit_thenTrueAndAtLimitThenFalse() {
        #expect(IntentTiming.shouldKeepWaiting(startedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(7.9)))
        #expect(!IntentTiming.shouldKeepWaiting(startedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(8)))
        #expect(!IntentTiming.shouldKeepWaiting(startedAt: Fixture.t0, now: Fixture.t0.addingTimeInterval(1), limit: 1))
        #expect(IntentTiming.pollInterval > 0)
    }
}
