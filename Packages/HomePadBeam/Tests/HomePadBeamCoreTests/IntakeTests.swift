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

@Suite struct BeamInboxTests {
    @Test func enqueue_whenSamePageFromSameDevice_thenDuplicate() {
        var inbox = BeamInbox()
        let beam = Fixture.beam()
        #expect(inbox.enqueue(beam, now: Fixture.now) == .queued)
        #expect(inbox.enqueue(beam, now: Fixture.now) == .duplicate)
        #expect(inbox.enqueue(Fixture.beam(), now: Fixture.now) == .duplicate)
        #expect(inbox.enqueue(Fixture.beam(sender: Fixture.otherPhone), now: Fixture.now) == .queued)
        #expect(inbox.pending.count == 2)
    }

    @Test func enqueue_whenOverLimit_thenDropsOldest() {
        var inbox = BeamInbox(pendingLimit: 2)
        let beams = (0..<3).map { Fixture.beam("https://example.com/\($0)") }
        for beam in beams {
            #expect(inbox.enqueue(beam, now: Fixture.now) == .queued)
        }
        #expect(inbox.pending == Array(beams.suffix(2)))
        #expect(inbox.resolve(id: beams[0].id) == nil)
    }

    @Test func resolve_whenPending_thenRemovesAndReturns() {
        var inbox = BeamInbox()
        let beam = Fixture.beam()
        _ = inbox.enqueue(beam, now: Fixture.now)
        #expect(inbox.resolve(id: beam.id) == beam)
        #expect(inbox.pending.isEmpty)
        #expect(inbox.resolve(id: beam.id) == nil)
    }

    @Test func pruneExpired_whenOlderThanLifetime_thenRemoved() {
        var inbox = BeamInbox(pendingLifetime: 60)
        let old = Fixture.beam("https://example.com/old")
        let fresh = Fixture.beam("https://example.com/new")
        _ = inbox.enqueue(old, now: Fixture.now)
        _ = inbox.enqueue(fresh, now: Fixture.now.addingTimeInterval(30))
        #expect(inbox.pruneExpired(now: Fixture.now.addingTimeInterval(59)) == [])
        #expect(inbox.pruneExpired(now: Fixture.now.addingTimeInterval(60)) == [old])
        #expect(inbox.pending == [fresh])
        #expect(inbox.enqueue(Fixture.beam("https://example.com/later"), now: Fixture.now.addingTimeInterval(200)) == .queued)
        #expect(inbox.pending.map(\.url.path) == ["/later"])
    }

    @Test func recordOpened_whenSamePageAgain_thenMovesToFrontWithoutDuplicate() {
        var inbox = BeamInbox(historyLimit: 3)
        let pages = (0..<4).map { Fixture.beam("https://example.com/\($0)") }
        for page in pages { inbox.recordOpened(page) }
        #expect(inbox.history.map(\.url.path) == ["/3", "/2", "/1"])
        inbox.recordOpened(Fixture.beam("https://example.com/1"))
        #expect(inbox.history.map(\.url.path) == ["/1", "/3", "/2"])
        inbox.clearHistory()
        #expect(inbox.history.isEmpty)
    }

    @Test func removeAll_whenDeviceRevoked_thenDropsItsPendingAndHistory() {
        var inbox = BeamInbox()
        let mine = Fixture.beam("https://example.com/a")
        let theirs = Fixture.beam("https://example.com/b", sender: Fixture.otherPhone)
        _ = inbox.enqueue(mine, now: Fixture.now)
        _ = inbox.enqueue(theirs, now: Fixture.now)
        inbox.recordOpened(mine)
        inbox.recordOpened(theirs)
        inbox.removeAll(from: Fixture.phoneID)
        #expect(inbox.pending == [theirs])
        #expect(inbox.history == [theirs])
        #expect(inbox.pruneExpired(now: Fixture.now.addingTimeInterval(601)) == [theirs])
    }
}

@Suite struct BeamIntakeTests {
    let open = BeamPreferences(approvalModeValue: "openImmediately")
    let ask = BeamPreferences()
    let source = BeamSource.peerLink(deviceID: Fixture.phoneID)

    private func receive(_ intake: inout BeamIntake, _ beam: BeamPayload, source: BeamSource? = nil, preferences: BeamPreferences? = nil, guest: Bool = false, approved: Int = 1, at offset: TimeInterval = 0) -> BeamIntakeResult {
        intake.receive(beam, source: source ?? self.source, preferences: preferences ?? open, isGuest: guest, senderApprovedBeamCount: approved, now: Fixture.now.addingTimeInterval(offset))
    }

    @Test func receive_whenTrustedAndOpenImmediately_thenOpensAndRecordsHistory() {
        var intake = BeamIntake()
        let beam = Fixture.beam()
        let result = receive(&intake, beam)
        guard case .open(let approved) = result else {
            Issue.record("expected open, got \(result)")
            return
        }
        #expect(approved.payload == beam)
        #expect(approved.url.url == beam.url)
        #expect(approved.source == source)
        #expect(approved.id == beam.id)
        #expect(result.outcome == .opened)
        #expect(intake.inbox.history == [beam])
        #expect(intake.inbox.pending.isEmpty)
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "https://user:pw@example.com/", "http://192.168.1.1/"])
    func receive_whenURLFailsPolicy_thenRejectedAndNothingQueued(text: String) {
        var intake = BeamIntake()
        let result = receive(&intake, Fixture.beam(text))
        guard case .rejected(let reason) = result else {
            Issue.record("expected rejection for \(text), got \(result)")
            return
        }
        #expect(result.outcome == .rejected(reason))
        #expect(intake.inbox.pending.isEmpty)
        #expect(intake.inbox.history.isEmpty)
    }

    @Test func receive_whenLocalAddressesAllowed_thenLocalPageOpens() {
        var intake = BeamIntake()
        let preferences = BeamPreferences(approvalModeValue: "openImmediately", allowLocalAddresses: true)
        #expect(receive(&intake, Fixture.beam("http://192.168.1.20/recipes"), preferences: preferences).outcome == .opened)
    }

    @Test func receive_whenAskFirstOrGuestOrFirstBeam_thenPendingWithReason() {
        var intake = BeamIntake()
        let first = Fixture.beam("https://example.com/1")
        #expect(receive(&intake, first, preferences: ask) == .pending(first, .hubPrefersAsking))
        let second = Fixture.beam("https://example.com/2")
        #expect(receive(&intake, second, guest: true) == .pending(second, .guestSession))
        let third = Fixture.beam("https://example.com/3")
        let result = receive(&intake, third, approved: 0)
        #expect(result == .pending(third, .firstBeamFromDevice))
        #expect(result.outcome == .awaitingApproval)
        #expect(intake.inbox.pending == [first, second, third])
        #expect(intake.inbox.history.isEmpty)
    }

    @Test func receive_whenSamePageAlreadyWaiting_thenDuplicate() {
        var intake = BeamIntake()
        _ = receive(&intake, Fixture.beam(), preferences: ask)
        let result = receive(&intake, Fixture.beam(), preferences: ask)
        #expect(result == .duplicate)
        #expect(result.outcome == .awaitingApproval)
        #expect(intake.inbox.pending.count == 1)
    }

    @Test func receive_whenDeviceExceedsRate_thenRateLimitedUntilWindowPasses() {
        var intake = BeamIntake(limit: 2, window: 30)
        #expect(receive(&intake, Fixture.beam("https://example.com/1")).outcome == .opened)
        #expect(receive(&intake, Fixture.beam("https://example.com/2"), at: 1).outcome == .opened)
        let limited = receive(&intake, Fixture.beam("https://example.com/3"), at: 2)
        #expect(limited == .rateLimited)
        #expect(limited.outcome == .rateLimited)
        #expect(intake.inbox.history.count == 2)
        let other = receive(&intake, Fixture.beam("https://example.com/4", sender: Fixture.otherPhone), source: .peerLink(deviceID: Fixture.otherPhoneID), at: 2)
        #expect(other.outcome == .opened)
        #expect(receive(&intake, Fixture.beam("https://example.com/5"), at: 31.5).outcome == .opened)
    }

    @Test func receive_whenSourceIsNotPeerLink_thenNotRateLimited() {
        var intake = BeamIntake(limit: 1, window: 30)
        for index in 0..<3 {
            #expect(receive(&intake, Fixture.beam("https://example.com/\(index)"), source: .handoff).outcome == .opened)
        }
        let link = Fixture.beam("https://example.com/link")
        #expect(receive(&intake, link, source: .deepLink) == .pending(link, .untrustedSource))
    }

    @Test func receive_whenHistoryOff_thenOpensWithoutRecording() {
        var intake = BeamIntake()
        let preferences = BeamPreferences(approvalModeValue: "openImmediately", keepHistory: false)
        #expect(receive(&intake, Fixture.beam(), preferences: preferences).outcome == .opened)
        #expect(intake.inbox.history.isEmpty)
    }

    @Test func approve_whenPending_thenOpensWithOriginalSource() throws {
        var intake = BeamIntake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: ask)
        let result = intake.approve(id: beam.id, preferences: ask)
        let approved = try #require(result)
        #expect(approved.payload == beam)
        #expect(approved.source == source)
        #expect(intake.inbox.pending.isEmpty)
        #expect(intake.inbox.history == [beam])
        #expect(intake.approve(id: beam.id, preferences: ask) == nil)
    }

    @Test func approve_whenPolicyTightenedWhileWaiting_thenRefuses() {
        var intake = BeamIntake()
        let local = Fixture.beam("http://192.168.1.20/")
        let relaxed = BeamPreferences(allowLocalAddresses: true)
        #expect(receive(&intake, local, preferences: relaxed) == .pending(local, .hubPrefersAsking))
        #expect(intake.approve(id: local.id, preferences: ask) == nil)
        #expect(intake.inbox.pending.isEmpty)
        #expect(intake.inbox.history.isEmpty)
    }

    @Test func decline_whenPending_thenRemovedWithoutHistory() throws {
        var intake = BeamIntake()
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: ask)
        let result = intake.decline(id: beam.id)
        let declined = try #require(result)
        #expect(declined.beam == beam)
        #expect(declined.source == source)
        #expect(intake.inbox.history.isEmpty)
        #expect(intake.decline(id: beam.id) == nil)
    }

    @Test func reopen_whenFromRecents_thenValidatesAgain() {
        var intake = BeamIntake()
        let reopened = intake.reopen(Fixture.beam(), preferences: ask)
        #expect(reopened?.url.url.host() == "example.com")
        #expect(intake.reopen(Fixture.beam("http://10.0.0.1/"), preferences: ask) == nil)
    }

    @Test func applyHistoryPreference_whenTurnedOff_thenClears() {
        var intake = BeamIntake()
        _ = receive(&intake, Fixture.beam())
        intake.applyHistoryPreference(keepHistory: true)
        #expect(intake.inbox.history.count == 1)
        intake.applyHistoryPreference(keepHistory: false)
        #expect(intake.inbox.history.isEmpty)
    }

    @Test func pruneExpired_whenWaitingTooLong_thenDropsAndForgetsSource() {
        var intake = BeamIntake(inbox: BeamInbox(pendingLifetime: 60))
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: ask)
        #expect(intake.pruneExpired(now: Fixture.now.addingTimeInterval(61)) == [beam])
        #expect(intake.approve(id: beam.id, preferences: ask) == nil)
    }

    @Test func forget_whenDeviceRevoked_thenDropsItsBeamsAndRateState() {
        var intake = BeamIntake(limit: 1, window: 30)
        let beam = Fixture.beam()
        _ = receive(&intake, beam, preferences: ask)
        #expect(receive(&intake, Fixture.beam("https://example.com/2"), preferences: ask) == .rateLimited)
        intake.forget(deviceID: Fixture.phoneID)
        #expect(intake.inbox.pending.isEmpty)
        #expect(intake.approve(id: beam.id, preferences: ask) == nil)
        #expect(receive(&intake, Fixture.beam("https://example.com/3"), preferences: ask).outcome == .awaitingApproval)
    }
}
