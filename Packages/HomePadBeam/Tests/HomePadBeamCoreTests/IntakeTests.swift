import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct BeamApprovalPolicyTests {
    private func decide(_ source: BeamSource, mode: BeamApprovalMode = .openImmediately, guest: Bool = false, approved: Int = 1) -> BeamApprovalDecision {
        BeamApprovalPolicy.decide(source: source, mode: mode, isGuest: guest, senderApprovedBeamCount: approved)
    }

    @Test func decide_whenPeerLinkAndTrustedSenderAndOpenImmediately_thenOpens() {
        #expect(decide(.peerLink(deviceID: Fixture.phoneID)) == .openNow)
    }

    @Test func decide_whenHubPrefersAsking_thenAsks() {
        #expect(decide(.peerLink(deviceID: Fixture.phoneID), mode: .askFirst) == .ask(.hubPrefersAsking))
    }

    @Test func decide_whenGuest_thenAsksEvenIfOpenImmediately() {
        #expect(decide(.peerLink(deviceID: Fixture.phoneID), guest: true) == .ask(.guestSession))
    }

    @Test func decide_whenFirstBeamFromDevice_thenAsks() {
        #expect(decide(.peerLink(deviceID: Fixture.phoneID), approved: 0) == .ask(.firstBeamFromDevice))
    }

    @Test func decide_whenDeepLink_thenAlwaysAsks() {
        #expect(decide(.deepLink) == .ask(.untrustedSource))
    }

    @Test func decide_whenStartedOnTheHub_thenOpens() {
        #expect(decide(.handoff, mode: .askFirst, guest: true, approved: 0) == .openNow)
        #expect(decide(.sharePlay, mode: .askFirst, guest: true, approved: 0) == .openNow)
    }

    @Test func modeInit_whenValueUnknown_thenAsksFirst() {
        #expect(BeamApprovalMode(settingValue: "openImmediately") == .openImmediately)
        #expect(BeamApprovalMode(settingValue: "askFirst") == .askFirst)
        #expect(BeamApprovalMode(settingValue: "whatever") == .askFirst)
    }
}

@Suite struct RateLimiterTests {
    @Test func allow_whenOverLimitInsideWindow_thenRefusesUntilWindowPasses() {
        var limiter = RateLimiter<String>(limit: 2, window: 10)
        #expect(limiter.allow("a", now: Fixture.now) == true)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(1)) == true)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(2)) == false)
        #expect(limiter.allow("b", now: Fixture.now.addingTimeInterval(2)) == true)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(9.9)) == false)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(10)) == true)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(10.5)) == false)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(11)) == true)
        #expect(limiter.allow("a", now: Fixture.now.addingTimeInterval(100)) == true)
    }

    @Test func reset_whenCalled_thenKeyStartsFresh() {
        var limiter = RateLimiter<String>(limit: 1, window: 10)
        #expect(limiter.allow("a", now: Fixture.now) == true)
        limiter.reset("a")
        #expect(limiter.allow("a", now: Fixture.now) == true)
        #expect(limiter.limit == 1 && limiter.window == 10)
    }
}

@Suite struct BeamIntakeTests {
    static let open = BeamPreferences(approvalModeValue: "openImmediately")
    static let ask = BeamPreferences()
    static let fromPhone = BeamSource.peerLink(deviceID: Fixture.phoneID)
    static let fromOtherPhone = BeamSource.peerLink(deviceID: Fixture.otherPhoneID)
    static let ada = BrowserOwner.member(Fixture.profileID)
    static let bo = BrowserOwner.member(Fixture.otherProfileID)

    /// An intake with Ada in front of the hub unless told otherwise. The phone is Ada's.
    private func intake(
        active profileID: UUID? = Fixture.profileID,
        limit: Int = BeamIntake.beamsPerWindow,
        waitingLimit: Int = BeamIntake.defaultWaitingLimit,
        waitingLifetime: TimeInterval = BeamIntake.defaultWaitingLifetime
    ) -> BeamIntake {
        var intake = BeamIntake(limit: limit, window: 30, waitingLimit: waitingLimit, waitingLifetime: waitingLifetime)
        arrive(&intake, profileID)
        return intake
    }

    @discardableResult
    private func arrive(
        _ intake: inout BeamIntake,
        _ profileID: UUID?,
        signsOut: Bool? = nil,
        preferences: BeamPreferences = open,
        approved: Int = 1,
        dataStore: BrowserDataStore = .ephemeral,
        at offset: TimeInterval = 0
    ) -> BrowserSignOut? {
        // As the household session does: the generation moves when the person changes, and
        // when the same person signs out.
        let changes = signsOut ?? (BrowserOwner(activeProfileID: profileID) != intake.active)
        let generation = intake.browser.presence.audienceGeneration + (changes ? 1 : 0)
        return intake.presenceChanged(
            to: Fixture.presence(profileID, generation: generation),
            preferences: preferences,
            approvedBeamCount: { _ in approved },
            dataStore: dataStore,
            now: Fixture.now.addingTimeInterval(offset)
        )
    }

    private func receive(
        _ intake: inout BeamIntake,
        _ beam: BeamPayload,
        source: BeamSource = fromPhone,
        sender profileID: UUID? = Fixture.profileID,
        preferences: BeamPreferences = open,
        approved: Int = 1,
        dataStore: BrowserDataStore = .ephemeral,
        at offset: TimeInterval = 0
    ) -> BeamIntakeResult {
        intake.receive(
            beam,
            source: source,
            senderProfileID: profileID,
            householdProfileIDs: Fixture.household,
            preferences: preferences,
            senderApprovedBeamCount: approved,
            dataStore: dataStore,
            now: Fixture.now.addingTimeInterval(offset)
        )
    }

    private func receipt(_ beam: BeamPayload, _ outcome: BeamOutcome, to deviceID: UUID = Fixture.phoneID) -> BeamReceiptNotice {
        BeamReceiptNotice(deviceID: deviceID, receipt: BeamReceipt(beamID: beam.id, outcome: outcome))
    }

    // MARK: The owner is in front

    @Test func receive_whenOwnerIsInFrontAndTrusted_thenOpensAsTheirPageAndTellsTheSender() {
        var intake = intake()
        let beam = Fixture.beam()
        let result = receive(&intake, beam)
        guard case .open(let approved) = result else {
            Issue.record("expected open, got \(result)")
            return
        }
        #expect(approved.payload == beam)
        #expect(approved.url.url == beam.url)
        #expect(approved.source == Self.fromPhone)
        #expect(result.outcome == .opened)
        #expect(intake.active == Self.ada)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beam.id])
        #expect(intake.browser.presented(for: Self.ada) == approved)
        #expect(intake.browser.recents(for: Self.ada) == [beam])
        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(beam, .opened)])
        #expect(intake.takeReceipts().isEmpty)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "https://user:pw@example.com/", "http://192.168.1.1/"])
    func receive_whenURLFailsPolicy_thenRejectedAndNothingKept(text: String) {
        var intake = intake()
        let beam = Fixture.beam(text)
        let result = receive(&intake, beam)
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejection for \(text), got \(result)")
            return
        }
        #expect(result.outcome == .rejected(reason))
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
        #expect(intake.waitingCount(for: Self.ada) == 0)
        #expect(intake.takeReceipts() == [receipt(beam, .rejected(reason))])
    }

    @Test func receive_whenLocalAddressesAllowed_thenLocalPageOpens() {
        var intake = intake()
        let preferences = BeamPreferences(approvalModeValue: "openImmediately", allowLocalAddresses: true)
        #expect(receive(&intake, Fixture.beam("http://192.168.1.20/recipes"), preferences: preferences).outcome == .opened)
    }

    @Test func receive_whenHubAsksFirstOrSenderIsNew_thenOfferedToTheOwnerInFront() {
        var intake = intake()
        let first = Fixture.beam("https://example.com/1")
        #expect(receive(&intake, first, preferences: Self.ask) == .pending(first, .hubPrefersAsking))
        let second = Fixture.beam("https://example.com/2")
        let result = receive(&intake, second, approved: 0)
        #expect(result == .pending(second, .firstBeamFromDevice))
        #expect(result.outcome == .awaitingApproval)
        #expect(intake.offers(for: Self.ada) == [first, second])
        #expect(intake.waitingCount(for: Self.ada) == 2)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(first, .awaitingApproval), receipt(second, .awaitingApproval)])
    }

    @Test func receive_whenPhoneBelongsToNobodyAndGuestIsInFront_thenOfferedToTheGuest() {
        var intake = intake(active: nil)
        let beam = Fixture.beam(sender: Fixture.otherPhone)
        #expect(receive(&intake, beam, source: Self.fromOtherPhone, sender: nil) == .pending(beam, .guestSession))
        #expect(intake.offers(for: .guest) == [beam])
    }

    @Test func receive_whenPhoneBelongsToNobody_thenThePersonInFrontOwnsThePage() {
        var intake = intake()
        let beam = Fixture.beam(sender: Fixture.otherPhone)
        #expect(receive(&intake, beam, source: Self.fromOtherPhone, sender: nil).outcome == .opened)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beam.id])
    }

    @Test func receive_whenStartedAtTheHub_thenThePersonInFrontOwnsThePage() {
        var intake = intake(active: Fixture.otherProfileID, limit: 1)
        for index in 0..<3 {
            let result = receive(&intake, Fixture.beam("https://example.com/\(index)"), source: .handoff, sender: Fixture.profileID)
            #expect(result.outcome == .opened)
        }
        #expect(intake.browser.pages(for: Self.bo).count == 3)
        let link = Fixture.beam("https://example.com/link")
        #expect(receive(&intake, link, source: .deepLink) == .pending(link, .untrustedSource))
        #expect(intake.offers(for: Self.bo) == [link])
        #expect(receive(&intake, Fixture.beam("https://example.com/together"), source: .sharePlay).outcome == .opened)
        #expect(intake.takeReceipts().isEmpty)
    }

    @Test func receive_whenDeviceExceedsRate_thenRateLimitedUntilWindowPasses() {
        var intake = intake(limit: 2)
        #expect(receive(&intake, Fixture.beam("https://example.com/1")).outcome == .opened)
        #expect(receive(&intake, Fixture.beam("https://example.com/2"), at: 1).outcome == .opened)
        let third = Fixture.beam("https://example.com/3")
        let limited = receive(&intake, third, at: 2)
        #expect(limited == .rateLimited)
        #expect(limited.outcome == .rateLimited)
        #expect(intake.takeReceipts().last == receipt(third, .rateLimited))
        #expect(intake.browser.pages(for: Self.ada).count == 2)
        let other = receive(&intake, Fixture.beam("https://example.com/4", sender: Fixture.otherPhone), source: Self.fromOtherPhone, sender: nil, at: 2)
        #expect(other.outcome == .opened)
        #expect(receive(&intake, Fixture.beam("https://example.com/5"), at: 31.5).outcome == .opened)
    }

    @Test func receive_whenHistoryOff_thenOpensWithoutRecording() {
        var intake = intake()
        let preferences = BeamPreferences(approvalModeValue: "openImmediately", keepHistory: false)
        #expect(receive(&intake, Fixture.beam(), preferences: preferences).outcome == .opened)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
    }

    // MARK: The owner is somewhere else

    @Test(arguments: [Fixture.otherProfileID as UUID?, nil])
    func receive_whenSenderIsNotThePersonInFront_thenHeldUnseenForTheOwner(inFront: UUID?) {
        var intake = intake(active: inFront)
        let viewer = BrowserOwner(activeProfileID: inFront)
        let beam = Fixture.beam()
        let result = receive(&intake, beam)
        #expect(result == .waitingForOwner(beam))
        #expect(result.outcome == .waitingForOwner)
        #expect(intake.takeReceipts() == [receipt(beam, .waitingForOwner)])
        #expect(intake.waitingCount(for: Self.ada) == 1)

        #expect(intake.offers(for: viewer).isEmpty)
        #expect(intake.browser.pages(for: viewer).isEmpty)
        #expect(intake.browser.frontPage(for: viewer) == nil)
        #expect(intake.browser.presented(for: viewer) == nil)
        #expect(intake.browser.recents(for: viewer).isEmpty)
        #expect(intake.browser.openPageIDs.isEmpty)
        #expect(intake.approve(id: beam.id, preferences: Self.open, dataStore: .ephemeral, now: Fixture.now) == nil)
        #expect(intake.decline(id: beam.id) == nil)

        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.waitingCount(for: Self.ada) == 1)
        #expect(intake.takeReceipts().isEmpty)
    }

    @Test func presenceChanged_whenOwnerArrivesAndHubOpensImmediately_thenHeldBeamsOpenNewestInFront() {
        var intake = intake(active: Fixture.otherProfileID)
        let first = Fixture.beam("https://example.com/1")
        let second = Fixture.beam("https://example.com/2")
        _ = receive(&intake, first)
        _ = receive(&intake, second, at: 1)
        _ = intake.takeReceipts()

        let signOut = arrive(&intake, Fixture.profileID, at: 60)
        #expect(signOut == BrowserSignOut(owner: Self.bo, closedPageIDs: []))
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [first.id, second.id])
        #expect(intake.browser.frontPage(for: Self.ada)?.id == second.id)
        #expect(intake.browser.recents(for: Self.ada) == [second, first])
        #expect(intake.waitingCount(for: Self.ada) == 0)
        #expect(intake.takeReceipts() == [receipt(first, .opened), receipt(second, .opened)])
        #expect(intake.browser.pages(for: Self.bo).isEmpty)
    }

    @Test func presenceChanged_whenOwnerArrivesAndHubAsks_thenHeldBeamsAreOfferedToThemOnly() {
        var intake = intake(active: nil)
        let first = Fixture.beam("https://example.com/1")
        let second = Fixture.beam("https://example.com/2")
        _ = receive(&intake, first)
        _ = receive(&intake, second)
        _ = intake.takeReceipts()

        arrive(&intake, Fixture.profileID, preferences: Self.ask)
        #expect(intake.offers(for: Self.ada) == [first, second])
        #expect(intake.offers(for: .guest).isEmpty)
        #expect(intake.offers(for: Self.bo).isEmpty)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(first, .awaitingApproval), receipt(second, .awaitingApproval)])
    }

    @Test func presenceChanged_whenHeldBeamIsTheFirstFromItsPhone_thenAsks() {
        var intake = intake(active: nil)
        let beam = Fixture.beam()
        _ = receive(&intake, beam)
        arrive(&intake, Fixture.profileID, approved: 0)
        #expect(intake.offers(for: Self.ada) == [beam])
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
    }

    @Test func presenceChanged_whenPolicyTightenedWhileBeamWasHeld_thenDroppedAndSenderTold() {
        var intake = intake(active: nil)
        let local = Fixture.beam("http://192.168.1.20/")
        let relaxed = BeamPreferences(approvalModeValue: "openImmediately", allowLocalAddresses: true)
        #expect(receive(&intake, local, preferences: relaxed) == .waitingForOwner(local))
        _ = intake.takeReceipts()
        arrive(&intake, Fixture.profileID)
        #expect(intake.waitingCount(for: Self.ada) == 0)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(local, .rejected(.localHost))])
    }

    @Test func presenceChanged_whenOwnerLeavesBeforeAnswering_thenOfferHidesAndReturnsWithThem() {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: Self.ask)
        _ = intake.takeReceipts()

        arrive(&intake, Fixture.otherProfileID)
        #expect(intake.offers(for: Self.bo).isEmpty)
        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.approve(id: beam.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)
        #expect(intake.decline(id: beam.id) == nil)

        arrive(&intake, Fixture.profileID)
        #expect(intake.offers(for: Self.ada) == [beam])
        #expect(intake.takeReceipts().isEmpty)
    }

    @Test func receive_whenSamePageAlreadyHeld_thenDuplicateSaysWhereItStands() {
        var intake = intake(active: nil)
        #expect(receive(&intake, Fixture.beam()).outcome == .waitingForOwner)
        let again = receive(&intake, Fixture.beam())
        #expect(again == .duplicate(.waitingForOwner))
        #expect(again.outcome == .waitingForOwner)
        #expect(intake.waitingCount(for: Self.ada) == 1)

        arrive(&intake, Fixture.profileID, preferences: Self.ask)
        let asked = receive(&intake, Fixture.beam(), preferences: Self.ask)
        #expect(asked == .duplicate(.awaitingApproval))
        #expect(intake.offers(for: Self.ada).count == 1)
    }

    @Test func receive_whenMoreHeldThanTheLimit_thenOldestIsLetGoAndItsSenderTold() {
        var intake = intake(active: nil, waitingLimit: 2)
        let beams = (0..<3).map { Fixture.beam("https://example.com/\($0)") }
        for beam in beams {
            #expect(receive(&intake, beam) == .waitingForOwner(beam))
        }
        #expect(intake.waitingCount(for: Self.ada) == 2)
        #expect(intake.takeReceipts() == [
            receipt(beams[0], .waitingForOwner), receipt(beams[1], .waitingForOwner),
            receipt(beams[0], .expired), receipt(beams[2], .waitingForOwner),
        ])
        arrive(&intake, Fixture.profileID)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beams[1].id, beams[2].id])
        #expect(BeamIntake(waitingLimit: 0).waitingLimit == 1)
    }

    @Test func pruneExpired_whenHeldLongerThanLifetime_thenDroppedAndSendersTold() {
        var intake = intake(active: nil, waitingLifetime: 60)
        #expect(intake.nextExpiry == nil)
        let old = Fixture.beam("https://example.com/old")
        let fresh = Fixture.beam("https://example.com/new", sender: Fixture.otherPhone)
        _ = receive(&intake, old)
        _ = receive(&intake, fresh, source: Self.fromOtherPhone, sender: Fixture.otherProfileID, at: 30)
        _ = intake.takeReceipts()
        #expect(intake.nextExpiry == Fixture.now.addingTimeInterval(60))
        #expect(intake.pruneExpired(now: Fixture.now.addingTimeInterval(59)) == [])
        #expect(intake.pruneExpired(now: Fixture.now.addingTimeInterval(60)) == [old])
        #expect(intake.takeReceipts() == [receipt(old, .expired)])
        #expect(intake.nextExpiry == Fixture.now.addingTimeInterval(90))

        arrive(&intake, Fixture.profileID, at: 61)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        arrive(&intake, Fixture.otherProfileID, at: 200)
        #expect(intake.browser.pages(for: Self.bo).isEmpty)
        #expect(intake.takeReceipts() == [receipt(fresh, .expired, to: Fixture.otherPhoneID)])
        let later = Fixture.beam("https://example.com/later")
        _ = receive(&intake, later, at: 300)
        #expect(receive(&intake, Fixture.beam("https://example.com/last"), at: 400) != .duplicate(.waitingForOwner))
        #expect(intake.waitingCount(for: Self.ada) == 1)
    }

    @Test func pruneExpired_whenSeveralOwnersBeamsRunOut_thenSendersAreToldOldestFirst() {
        var intake = intake(active: nil, waitingLifetime: 60)
        let forBo = Fixture.beam("https://example.com/bo", sender: Fixture.otherPhone)
        let forAda = Fixture.beam("https://example.com/ada")
        _ = receive(&intake, forBo, source: Self.fromOtherPhone, sender: Fixture.otherProfileID)
        _ = receive(&intake, forAda, at: 5)
        _ = intake.takeReceipts()
        #expect(intake.pruneExpired(now: Fixture.now.addingTimeInterval(120)) == [forBo, forAda])
        #expect(intake.takeReceipts() == [receipt(forBo, .expired, to: Fixture.otherPhoneID), receipt(forAda, .expired)])
        #expect(intake.nextExpiry == nil)
    }

    @Test func queries_whenNothingWasEverHeld_thenEmpty() {
        let intake = BeamIntake()
        #expect(intake.active == .guest)
        #expect(intake.offers(for: .guest).isEmpty)
        #expect(intake.waitingCount(for: .guest) == 0)
        #expect(intake.waitingLifetime == 30 * 60)
        #expect(intake.waitingLimit == 6)
    }

    // MARK: Answers

    @Test func approve_whenOffered_thenOpensWithOriginalSourceAndTellsTheSender() throws {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: Self.ask)
        _ = intake.takeReceipts()
        let result = intake.approve(id: beam.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now)
        let approved = try #require(result)
        #expect(approved.payload == beam)
        #expect(approved.source == Self.fromPhone)
        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beam.id])
        #expect(intake.browser.recents(for: Self.ada) == [beam])
        #expect(intake.takeReceipts() == [receipt(beam, .opened)])
        #expect(intake.approve(id: beam.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)
    }

    @Test func approve_whenPolicyTightenedWhileWaiting_thenRefusesAndTellsTheSender() {
        var intake = intake()
        let local = Fixture.beam("http://192.168.1.20/")
        let relaxed = BeamPreferences(allowLocalAddresses: true)
        #expect(receive(&intake, local, preferences: relaxed) == .pending(local, .hubPrefersAsking))
        _ = intake.takeReceipts()
        #expect(intake.approve(id: local.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)
        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(local, .rejected(.localHost))])
    }

    @Test func decline_whenOffered_thenRemovedWithoutOpening() {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: Self.ask)
        _ = intake.takeReceipts()
        #expect(intake.decline(id: beam.id) == beam)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
        #expect(intake.takeReceipts() == [receipt(beam, .declined)])
        #expect(intake.decline(id: beam.id) == nil)
    }

    @Test func reopen_whenInTheirOwnRecents_thenOpensAfterCheckingTheAddressAgain() throws {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam)
        intake.closeAllPages()
        let result = intake.reopen(recentID: beam.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now)
        let reopened = try #require(result)
        #expect(reopened.payload == beam)
        #expect(reopened.source == .deepLink)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beam.id])
        #expect(intake.reopen(recentID: UUID(), preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)

        let relaxed = BeamPreferences(approvalModeValue: "openImmediately", allowLocalAddresses: true)
        let local = Fixture.beam("http://192.168.1.20/")
        _ = receive(&intake, local, preferences: relaxed)
        intake.closeAllPages()
        #expect(intake.reopen(recentID: local.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)
    }

    @Test func reopen_whenPageIsInSomeoneElsesRecents_thenDoesNotOpen() {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam)
        arrive(&intake, Fixture.otherProfileID)
        #expect(intake.reopen(recentID: beam.id, preferences: Self.open, dataStore: .ephemeral, now: Fixture.now) == nil)
        #expect(intake.browser.pages(for: Self.bo).isEmpty)
        #expect(intake.browser.openPageIDs.isEmpty)
    }

    // MARK: Sign out

    @Test func presenceChanged_whenOwnerSignsOut_thenEveryPageOfTheirsCloses() {
        var intake = intake()
        let beams = (0..<3).map { Fixture.beam("https://example.com/\($0)") }
        for beam in beams { _ = receive(&intake, beam) }
        #expect(intake.browser.openPageIDs == Set(beams.map(\.id)))

        let signOut = arrive(&intake, nil)
        #expect(signOut == BrowserSignOut(owner: Self.ada, closedPageIDs: beams.map(\.id)))
        #expect(intake.browser.openPageIDs.isEmpty)
        #expect(intake.browser.pages(for: .guest).isEmpty)
        #expect(intake.browser.recents(for: .guest).isEmpty)

        #expect(arrive(&intake, Fixture.profileID) == BrowserSignOut(owner: .guest, closedPageIDs: []))
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.browser.recents(for: Self.ada).map(\.id) == beams.reversed().map(\.id))
        #expect(arrive(&intake, Fixture.profileID) == nil)
    }

    @Test func presenceChanged_whenGuestLeaves_thenTheirOffersAreDroppedAndSendersTold() {
        var intake = intake(active: nil)
        let beam = Fixture.beam(sender: Fixture.otherPhone)
        _ = receive(&intake, beam, source: Self.fromOtherPhone, sender: nil)
        let link = Fixture.beam("https://example.com/link", sender: Fixture.hub)
        _ = receive(&intake, link, source: .deepLink, sender: nil)
        let held = Fixture.beam("https://example.com/held")
        _ = receive(&intake, held)
        _ = intake.takeReceipts()
        #expect(intake.offers(for: .guest) == [beam, link])

        let signOut = arrive(&intake, nil, signsOut: true)
        #expect(signOut == BrowserSignOut(owner: .guest, closedPageIDs: []))
        #expect(intake.offers(for: .guest).isEmpty)
        #expect(intake.waitingCount(for: .guest) == 0)
        #expect(intake.waitingCount(for: Self.ada) == 1)
        #expect(intake.takeReceipts() == [receipt(beam, .expired, to: Fixture.otherPhoneID)])
    }

    @Test func presenceChanged_whenTheCameraLosesSightButNobodySignedOut_thenPagesStayOpenAndOnScreen() {
        var intake = intake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam)
        #expect(arrive(&intake, Fixture.profileID, signsOut: false, at: 30) == nil)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [beam.id])
        #expect(intake.browser.presented(for: Self.ada)?.id == beam.id)

        #expect(arrive(&intake, Fixture.profileID, signsOut: true, at: 150) == BrowserSignOut(owner: Self.ada, closedPageIDs: [beam.id]))
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
        #expect(intake.browser.openPageIDs.isEmpty)
    }

    @Test func open_whenPageOpens_thenItKeepsTheDataStoreOfThatMoment() {
        let mine = BrowserDataStore.profile(Fixture.profileID)
        var intake = intake(active: nil)
        let held = Fixture.beam("https://example.com/held")
        _ = receive(&intake, held, dataStore: .ephemeral)
        arrive(&intake, Fixture.profileID, dataStore: mine)
        let direct = Fixture.beam("https://example.com/direct")
        _ = receive(&intake, direct, dataStore: .ephemeral)
        let asked = Fixture.beam("https://example.com/asked")
        _ = receive(&intake, asked, preferences: Self.ask)
        _ = intake.approve(id: asked.id, preferences: Self.ask, dataStore: mine, now: Fixture.now)
        #expect(intake.browser.pages(for: Self.ada).map(\.dataStore) == [mine, .ephemeral, mine])

        intake.closeAllPages()
        _ = intake.reopen(recentID: direct.id, preferences: Self.open, dataStore: mine, now: Fixture.now)
        #expect(intake.browser.pages(for: Self.ada).map(\.dataStore) == [mine])
    }

    // MARK: Pages

    @Test func pageActions_whenForwarded_thenChangeTheSessionOfThePersonInFront() throws {
        var intake = intake()
        let first = Fixture.beam("https://example.com/1")
        let second = Fixture.beam("https://example.com/2")
        _ = receive(&intake, first)
        _ = receive(&intake, second)
        intake.selectPage(first.id)
        #expect(intake.browser.frontPage(for: Self.ada)?.id == first.id)

        let childID = UUID()
        let url = try #require(Fixture.validated("https://example.com/child"))
        let child = intake.openChildPage(of: first.id, url: url, id: childID, now: Fixture.now)
        #expect(child?.id == childID)
        #expect(intake.browser.frontPage(for: Self.ada)?.id == childID)

        intake.putAway()
        #expect(intake.browser.presented(for: Self.ada) == nil)
        #expect(intake.browser.pages(for: Self.ada).count == 3)
        intake.closePage(childID)
        #expect(intake.browser.pages(for: Self.ada).map(\.id) == [first.id, second.id])
        intake.closeAllPages()
        #expect(intake.browser.pages(for: Self.ada).isEmpty)
    }

    // MARK: Upkeep

    @Test func applyHistoryPreference_whenTurnedOff_thenClears() {
        var intake = intake()
        _ = receive(&intake, Fixture.beam())
        intake.applyHistoryPreference(keepHistory: true)
        #expect(intake.browser.recents(for: Self.ada).count == 1)
        intake.applyHistoryPreference(keepHistory: false)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
    }

    @Test func forget_whenDeviceRevoked_thenDropsWhatItSentAndItsRateState() {
        var intake = intake(limit: 2)
        let opened = Fixture.beam("https://example.com/1")
        let offered = Fixture.beam("https://example.com/2")
        _ = receive(&intake, opened)
        _ = receive(&intake, offered, preferences: Self.ask)
        #expect(receive(&intake, Fixture.beam("https://example.com/3")) == .rateLimited)
        intake.forget(deviceID: Fixture.phoneID)
        #expect(intake.takeReceipts().isEmpty)
        #expect(intake.offers(for: Self.ada).isEmpty)
        #expect(intake.browser.recents(for: Self.ada).isEmpty)
        #expect(intake.approve(id: offered.id, preferences: Self.ask, dataStore: .ephemeral, now: Fixture.now) == nil)
        #expect(receive(&intake, Fixture.beam("https://example.com/4"), preferences: Self.ask).outcome == .awaitingApproval)
    }
}
