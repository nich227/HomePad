import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct BrowserOwnerTests {
    let ada = BrowserOwner.member(Fixture.profileID)

    @Test func initWithProfile_whenNobodyIsRecognized_thenGuest() {
        #expect(BrowserOwner(activeProfileID: nil) == .guest)
        #expect(BrowserOwner(activeProfileID: Fixture.profileID) == ada)
        #expect(BrowserOwner.guest.profileID == nil)
        #expect(ada.profileID == Fixture.profileID)
    }

    @Test func owner_whenSentByAPairedPhone_thenTheMemberThePhoneBelongsTo() {
        let source = BeamSource.peerLink(deviceID: Fixture.phoneID)
        for active in [BrowserOwner.guest, .member(Fixture.otherProfileID), ada] {
            #expect(BrowserOwner.owner(of: source, senderProfileID: Fixture.profileID, householdProfileIDs: Fixture.household, active: active) == ada)
        }
    }

    @Test func owner_whenPhoneHasNoMemberOrItsMemberWasRemoved_thenThePersonInFront() {
        let source = BeamSource.peerLink(deviceID: Fixture.phoneID)
        let bo = BrowserOwner.member(Fixture.otherProfileID)
        #expect(BrowserOwner.owner(of: source, senderProfileID: nil, householdProfileIDs: Fixture.household, active: bo) == bo)
        #expect(BrowserOwner.owner(of: source, senderProfileID: Fixture.profileID, householdProfileIDs: [Fixture.otherProfileID], active: bo) == bo)
        #expect(BrowserOwner.owner(of: source, senderProfileID: Fixture.profileID, householdProfileIDs: [], active: .guest) == .guest)
    }

    @Test(arguments: [BeamSource.deepLink, .handoff, .sharePlay])
    func owner_whenStartedAtTheHub_thenThePersonInFront(source: BeamSource) {
        let bo = BrowserOwner.member(Fixture.otherProfileID)
        #expect(BrowserOwner.owner(of: source, senderProfileID: Fixture.profileID, householdProfileIDs: Fixture.household, active: bo) == bo)
        #expect(BrowserOwner.owner(of: source, senderProfileID: nil, householdProfileIDs: Fixture.household, active: .guest) == .guest)
    }

    @Test func signedOut_whenTheHouseholdSessionSaysSo_thenThePersonBefore() {
        let here = Fixture.presence(Fixture.profileID, generation: 4)
        #expect(here.signedOut(by: Fixture.presence(Fixture.otherProfileID, generation: 5)) == ada)
        #expect(here.signedOut(by: Fixture.presence(nil, generation: 5)) == ada)
        #expect(here.signedOut(by: Fixture.presence(Fixture.profileID, generation: 5)) == ada)
        #expect(Fixture.presence(nil, generation: 4).signedOut(by: Fixture.presence(nil, generation: 5)) == .guest)
        #expect(Fixture.presence(nil, generation: 3).signedOut(by: here) == .guest)
    }

    @Test func signedOut_whenTheGenerationIsUnchanged_thenNobody() {
        let here = Fixture.presence(Fixture.profileID, generation: 4)
        #expect(here.signedOut(by: here) == nil)
        #expect(here.signedOut(by: Fixture.presence(Fixture.profileID, generation: 4)) == nil)
        #expect(HubPresence.nobody.signedOut(by: .nobody) == nil)
        #expect(HubPresence.nobody.owner == .guest)
        #expect(HubPresence.nobody.audienceGeneration == 0)
    }

    @Test func signedOut_whenTheOwnerChangesWithoutTheGeneration_thenStillThePersonBefore() {
        let here = Fixture.presence(Fixture.profileID, generation: 4)
        #expect(here.signedOut(by: Fixture.presence(Fixture.otherProfileID, generation: 4)) == ada)
        #expect(here.signedOut(by: Fixture.presence(nil, generation: 4)) == ada)
    }
}

@Suite struct BrowserSessionsTests {
    static let ada = BrowserOwner.member(Fixture.profileID)
    static let bo = BrowserOwner.member(Fixture.otherProfileID)

    /// Sessions with Ada in front of the hub unless told otherwise.
    private func sessions(active profileID: UUID? = Fixture.profileID, pageLimit: Int = BrowserSessions.defaultPageLimit, recentsLimit: Int = BrowserSessions.defaultRecentsLimit) -> BrowserSessions {
        BrowserSessions(pageLimit: pageLimit, recentsLimit: recentsLimit, presence: Fixture.presence(profileID))
    }

    private func open(
        _ sessions: inout BrowserSessions,
        _ paths: [String],
        keepHistory: Bool = true,
        dataStore: BrowserDataStore = .ephemeral
    ) -> [ApprovedBeam] {
        paths.enumerated().map { index, path in
            let beam = Fixture.approved("https://example.com/\(path)", title: path)
            sessions.open(beam, keepHistory: keepHistory, dataStore: dataStore, now: Fixture.now.addingTimeInterval(Double(index)))
            return beam
        }
    }

    // MARK: Opening

    @Test func open_whenBeamOpens_thenItIsThePageInFrontOfItsOwnersSession() {
        var sessions = sessions()
        #expect(sessions.presence == Fixture.presence(Fixture.profileID))
        let beams = open(&sessions, ["a", "b"])
        #expect(sessions.pages(for: Self.ada).map(\.beam) == beams)
        #expect(sessions.pages(for: Self.ada).map(\.openedAt) == [Fixture.now, Fixture.now.addingTimeInterval(1)])
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[1].id)
        #expect(sessions.presented(for: Self.ada) == beams[1])
        #expect(sessions.recents(for: Self.ada) == [beams[1].payload, beams[0].payload])
        #expect(sessions.openPageIDs == Set(beams.map(\.id)))
    }

    @Test func open_whenBeamIsAlreadyOpen_thenItComesToTheFrontWithoutASecondPage() {
        var sessions = sessions()
        let beams = open(&sessions, ["a", "b"])
        sessions.open(beams[0], keepHistory: true, dataStore: .profile(Fixture.profileID), now: Fixture.now)
        #expect(sessions.pages(for: Self.ada).map(\.id) == beams.map(\.id))
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[0].id)
        #expect(sessions.pages(for: Self.ada).map(\.dataStore) == [.ephemeral, .ephemeral])
    }

    @Test func open_whenPagesOpenUnderDifferentLockStates_thenEachKeepsTheStoreItOpenedWith() throws {
        var sessions = sessions()
        let unlocked = open(&sessions, ["signed-in"], dataStore: .profile(Fixture.profileID))[0]
        let locked = open(&sessions, ["later"], dataStore: .ephemeral)[0]
        #expect(sessions.pages(for: Self.ada).map(\.dataStore) == [.profile(Fixture.profileID), .ephemeral])

        let url = try #require(Fixture.validated("https://example.com/popup"))
        let opened = sessions.openChild(of: unlocked.id, url: url, id: UUID(), now: Fixture.now)
        #expect(opened?.dataStore == .profile(Fixture.profileID))
        sessions.select(locked.id)
        sessions.select(unlocked.id)
        #expect(sessions.frontPage(for: Self.ada)?.dataStore == .profile(Fixture.profileID))
    }

    @Test func open_whenSessionIsFull_thenOldestPageNotInFrontCloses() {
        var sessions = sessions(pageLimit: 3)
        let beams = open(&sessions, ["a", "b", "c"])
        sessions.select(beams[0].id)
        let fourth = open(&sessions, ["d"])[0]
        #expect(sessions.pages(for: Self.ada).map(\.id) == [beams[0].id, beams[2].id, fourth.id])
        #expect(sessions.frontPage(for: Self.ada)?.id == fourth.id)
        let fifth = open(&sessions, ["e"])[0]
        #expect(sessions.pages(for: Self.ada).map(\.id) == [beams[2].id, fourth.id, fifth.id])
        #expect(sessions.openPageIDs.count == 3)
    }

    @Test func open_whenLimitIsOnePage_thenTheNewPageReplacesIt() {
        var sessions = sessions(pageLimit: 0)
        #expect(sessions.pageLimit == 1)
        let beams = open(&sessions, ["a", "b"])
        #expect(sessions.pages(for: Self.ada).map(\.id) == [beams[1].id])
        #expect(BrowserSessions().pageLimit == 6)
    }

    @Test func open_whenBeamIsARecipe_thenHandedOffInsteadOfBecomingAPage() {
        var sessions = sessions()
        let page = open(&sessions, ["a"])[0]
        let recipe = Fixture.approved("https://example.com/soup", kind: .recipe)
        sessions.open(recipe, keepHistory: true, dataStore: .ephemeral, now: Fixture.now)
        #expect(sessions.presented(for: Self.ada) == recipe)
        #expect(sessions.pages(for: Self.ada).map(\.id) == [page.id])
        #expect(sessions.recents(for: Self.ada).first == recipe.payload)
        #expect(sessions.presented(for: Self.bo) == nil)

        sessions.putAway()
        #expect(sessions.presented(for: Self.ada) == nil)
        #expect(sessions.pages(for: Self.ada).map(\.id) == [page.id])
        sessions.select(page.id)
        #expect(sessions.presented(for: Self.ada) == page)
    }

    @Test func open_whenRecipeArrivesWithNoPagesOpen_thenPuttingItAwayLeavesNothingPresented() {
        var sessions = sessions(active: nil)
        let recipe = Fixture.approved("https://example.com/soup", kind: .recipe)
        sessions.open(recipe, keepHistory: false, dataStore: .ephemeral, now: Fixture.now)
        #expect(sessions.presented(for: .guest) == recipe)
        #expect(sessions.openPageIDs.isEmpty)
        sessions.putAway()
        #expect(sessions.presented(for: .guest) == nil)
    }

    @Test func openChild_whenLinkAsksForANewWindow_thenItIsAnotherPageOfTheSameSession() throws {
        var sessions = sessions(pageLimit: 2)
        let beams = open(&sessions, ["a", "b"])
        let url = try #require(Fixture.validated("https://other.example.org/popup"))
        let id = UUID()
        let opened = sessions.openChild(of: beams[1].id, url: url, id: id, now: Fixture.now.addingTimeInterval(9))
        let child = try #require(opened)
        #expect(child.id == id)
        #expect(child.beam.url == url)
        #expect(child.beam.source == beams[1].source)
        #expect(child.beam.payload.sender == beams[1].payload.sender)
        #expect(child.beam.payload.title == nil)
        #expect(child.openedAt == Fixture.now.addingTimeInterval(9))
        #expect(sessions.pages(for: Self.ada).map(\.id) == [beams[1].id, id])
        #expect(sessions.frontPage(for: Self.ada)?.id == id)
        #expect(sessions.recents(for: Self.ada).count == 2)
    }

    @Test func openChild_whenParentIsNotOpenForThePersonInFront_thenNothingOpens() throws {
        var sessions = sessions()
        let beams = open(&sessions, ["a"])
        let url = try #require(Fixture.validated("https://other.example.org/popup"))
        #expect(sessions.openChild(of: UUID(), url: url, id: UUID(), now: Fixture.now) == nil)
        sessions.update(to: Fixture.presence(Fixture.otherProfileID))
        #expect(sessions.openChild(of: beams[0].id, url: url, id: UUID(), now: Fixture.now) == nil)
        #expect(sessions.openPageIDs.isEmpty)
    }

    // MARK: Switching and closing

    @Test func select_whenPageIsOpen_thenItComesToTheFront() {
        var sessions = sessions()
        let beams = open(&sessions, ["a", "b", "c"])
        sessions.select(beams[0].id)
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[0].id)
        sessions.select(UUID())
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[0].id)
    }

    @Test func close_whenPageInFrontCloses_thenTheNextOneTakesItsPlace() {
        var sessions = sessions()
        let beams = open(&sessions, ["a", "b", "c"])
        sessions.select(beams[1].id)
        sessions.close(beams[1].id)
        #expect(sessions.pages(for: Self.ada).map(\.id) == [beams[0].id, beams[2].id])
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[2].id)
        sessions.close(beams[2].id)
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[0].id)
        sessions.close(UUID())
        #expect(sessions.pages(for: Self.ada).count == 1)
        sessions.close(beams[0].id)
        #expect(sessions.pages(for: Self.ada).isEmpty)
        #expect(sessions.frontPage(for: Self.ada) == nil)
        #expect(sessions.presented(for: Self.ada) == nil)
    }

    @Test func close_whenPageBehindCloses_thenFrontStays() {
        var sessions = sessions()
        let beams = open(&sessions, ["a", "b"])
        sessions.close(beams[0].id)
        #expect(sessions.frontPage(for: Self.ada)?.id == beams[1].id)
        #expect(sessions.presented(for: Self.ada) == beams[1])
    }

    @Test func closeAll_whenPagesAreOpen_thenNoneAreLeftAndRecentsStay() {
        var sessions = sessions()
        _ = open(&sessions, ["a", "b"])
        sessions.closeAll()
        #expect(sessions.pages(for: Self.ada).isEmpty)
        #expect(sessions.presented(for: Self.ada) == nil)
        #expect(sessions.openPageIDs.isEmpty)
        #expect(sessions.recents(for: Self.ada).count == 2)
    }

    @Test func actions_whenThePersonInFrontHasNoSession_thenNothingHappens() {
        var sessions = sessions(active: nil)
        sessions.closeAll()
        sessions.putAway()
        sessions.close(UUID())
        sessions.select(UUID())
        sessions.clearRecents()
        sessions.forgetRecents(from: Fixture.phoneID)
        #expect(sessions.openPageIDs.isEmpty)
        #expect(sessions.presented(for: .guest) == nil)
    }

    // MARK: Only the owner sees it

    @Test(arguments: [BrowserOwner.guest, .member(Fixture.otherProfileID)])
    func queries_whenViewerIsNotTheOwner_thenNoPagesTitlesAddressesOrRecents(viewer: BrowserOwner) {
        var sessions = sessions()
        _ = open(&sessions, ["private-a", "private-b"])
        #expect(sessions.pages(for: viewer).isEmpty)
        #expect(sessions.frontPage(for: viewer) == nil)
        #expect(sessions.presented(for: viewer) == nil)
        #expect(sessions.recents(for: viewer).isEmpty)
        #expect(sessions.pages(for: Self.ada).count == 2)
    }

    @Test(arguments: [nil as UUID?, Fixture.otherProfileID])
    func queries_whenSomeoneElseIsInFront_thenTheOwnersSessionAnswersNobody(inFront: UUID?) {
        var sessions = sessions()
        _ = open(&sessions, ["private-a", "private-b"])
        let viewer = BrowserOwner(activeProfileID: inFront)
        sessions.update(to: Fixture.presence(inFront))
        for asker in [viewer, Self.ada] {
            #expect(sessions.pages(for: asker).isEmpty)
            #expect(sessions.frontPage(for: asker) == nil)
            #expect(sessions.presented(for: asker) == nil)
            #expect(sessions.recents(for: asker).isEmpty)
        }
        let theirs = open(&sessions, ["public"])
        #expect(sessions.pages(for: viewer).map(\.beam) == theirs)
        #expect(sessions.recents(for: viewer) == theirs.map(\.payload))
        #expect(sessions.pages(for: Self.ada).isEmpty)
        #expect(sessions.recents(for: Self.ada).isEmpty)
    }

    // MARK: Sign out

    @Test(arguments: [
        Fixture.presence(Fixture.otherProfileID, generation: 1),
        Fixture.presence(nil, generation: 1),
        Fixture.presence(Fixture.profileID, generation: 1),
    ])
    func update_whenOwnerSignsOut_thenEveryPageOfTheirsClosesAndNothingIsPresented(next: HubPresence) {
        var sessions = sessions()
        let beams = open(&sessions, ["a", "b", "c"])
        let recipe = Fixture.approved("https://example.com/soup", kind: .recipe)
        sessions.open(recipe, keepHistory: false, dataStore: .ephemeral, now: Fixture.now)

        let signOut = sessions.update(to: next)
        #expect(signOut == BrowserSignOut(owner: Self.ada, closedPageIDs: beams.map(\.id)))
        #expect(sessions.presence == next)
        #expect(sessions.openPageIDs.isEmpty)
        for viewer in [Self.ada, Self.bo, .guest] {
            #expect(sessions.pages(for: viewer).isEmpty)
            #expect(sessions.frontPage(for: viewer) == nil)
            #expect(sessions.presented(for: viewer) == nil)
        }

        sessions.update(to: Fixture.presence(Fixture.profileID, generation: 2))
        #expect(sessions.pages(for: Self.ada).isEmpty)
        #expect(sessions.presented(for: Self.ada) == nil)
        #expect(sessions.recents(for: Self.ada).map(\.id) == beams.reversed().map(\.id))
    }

    @Test(arguments: [Fixture.presence(Fixture.profileID, generation: 1), Fixture.presence(nil, generation: 1)])
    func update_whenGuestSignsOut_thenTheWholeGuestSessionIsForgotten(next: HubPresence) {
        var sessions = sessions(active: nil)
        let beams = open(&sessions, ["a", "b"])
        #expect(sessions.recents(for: .guest).count == 2)
        #expect(sessions.update(to: next) == BrowserSignOut(owner: .guest, closedPageIDs: beams.map(\.id)))
        #expect(sessions.openPageIDs.isEmpty)
        sessions.update(to: Fixture.presence(nil, generation: 2))
        #expect(sessions.pages(for: .guest).isEmpty)
        #expect(sessions.recents(for: .guest).isEmpty)
    }

    @Test func update_whenNobodySignedOut_thenPagesStayOpenAndOnScreen() {
        var sessions = BrowserSessions(presence: Fixture.presence(Fixture.profileID, generation: 7))
        let beams = open(&sessions, ["a", "b"])
        #expect(sessions.update(to: Fixture.presence(Fixture.profileID, generation: 7)) == nil)
        #expect(sessions.pages(for: Self.ada).map(\.id) == beams.map(\.id))
        #expect(sessions.presented(for: Self.ada) == beams[1])
        #expect(sessions.openPageIDs.count == 2)
    }

    @Test func update_whenDepartingPersonHadNoSession_thenNothingClosed() {
        var sessions = sessions()
        #expect(sessions.update(to: Fixture.presence(nil)) == BrowserSignOut(owner: Self.ada, closedPageIDs: []))
    }

    // MARK: Recents

    @Test func recents_whenSamePageOpensAgain_thenMovesToFrontWithoutDuplicate() {
        var sessions = sessions(recentsLimit: 3)
        _ = open(&sessions, ["0", "1", "2", "3"])
        #expect(sessions.recents(for: Self.ada).map(\.url.path) == ["/3", "/2", "/1"])
        _ = open(&sessions, ["1"])
        #expect(sessions.recents(for: Self.ada).map(\.url.path) == ["/1", "/3", "/2"])
        _ = open(&sessions, ["4"], keepHistory: false)
        #expect(sessions.recents(for: Self.ada).map(\.url.path) == ["/1", "/3", "/2"])
        #expect(BrowserSessions(recentsLimit: -1).recentsLimit == 0)
    }

    @Test func clearRecents_whenHistoryIsTurnedOff_thenEveryOwnersRecentsGo() {
        var sessions = sessions()
        _ = open(&sessions, ["a"])
        sessions.update(to: Fixture.presence(Fixture.otherProfileID))
        _ = open(&sessions, ["b"])
        sessions.clearRecents()
        #expect(sessions.recents(for: Self.bo).isEmpty)
        sessions.update(to: Fixture.presence(Fixture.profileID))
        #expect(sessions.recents(for: Self.ada).isEmpty)
    }

    @Test func forgetRecents_whenDeviceRevoked_thenOnlyItsPagesGo() {
        var sessions = sessions()
        let mine = Fixture.approved("https://example.com/a")
        let theirs = Fixture.approved("https://example.com/b", sender: Fixture.otherPhone)
        sessions.open(mine, keepHistory: true, dataStore: .ephemeral, now: Fixture.now)
        sessions.open(theirs, keepHistory: true, dataStore: .ephemeral, now: Fixture.now)
        sessions.forgetRecents(from: Fixture.phoneID)
        #expect(sessions.recents(for: Self.ada) == [theirs.payload])
        #expect(sessions.pages(for: Self.ada).count == 2)
    }
}
