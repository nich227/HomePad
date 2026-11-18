import Foundation
import HomePadCore
import Testing
@testable import HomePadBeamCore

@Suite struct BeamSettingsTests {
    @Test func descriptors_whenListed_thenOnePerKeyInBeamPaneWithPrefix() {
        let names = BeamSettings.descriptors.map(\.name)
        #expect(names == [
            "beam.receiveBeams", "beam.approvalMode", "beam.hubName", "beam.companionName",
            "beam.sharePlay", "beam.handoff", "beam.keepHistory", "beam.allowLocalAddresses",
        ])
        #expect(Set(names).count == names.count)
        #expect(BeamSettings.descriptors.allSatisfy { $0.pane == "Beam" && $0.name.hasPrefix("beam.") && !$0.title.isEmpty })
    }

    @Test func descriptors_whenApprovalMode_thenOptionsMatchTheModesAndDefaultAsks() throws {
        let descriptor = try #require(BeamSettings.descriptors.first { $0.name == BeamSettings.approvalMode.name })
        guard case .choice(let options) = descriptor.control else {
            Issue.record("approval mode must be a choice")
            return
        }
        #expect(options.map(\.value) == BeamApprovalMode.allCases.map(\.rawValue))
        #expect(descriptor.defaultValue == .string("askFirst"))
    }

    @Test func preferences_whenDefault_thenAskFirstAndNoLocalAddresses() {
        let preferences = BeamPreferences()
        #expect(preferences.receiveBeams)
        #expect(preferences.approvalMode == .askFirst)
        #expect(preferences.hubName == "HomePad")
        #expect(preferences.companionName == "iPhone")
        #expect(preferences.sharePlayEnabled && preferences.handoffEnabled && preferences.keepHistory)
        #expect(!preferences.allowLocalAddresses)
        #expect(preferences.urlPolicy == BeamURLPolicy(allowsLocalHosts: false))
    }

    @Test func preferences_whenNamesBlankOrModeUnknown_thenFallBack() {
        let preferences = BeamPreferences(approvalModeValue: "???", hubName: " \n", companionName: "", allowLocalAddresses: true)
        #expect(preferences.approvalMode == .askFirst)
        #expect(preferences.hubName == "HomePad")
        #expect(preferences.companionName == "iPhone")
        #expect(preferences.urlPolicy.allowsLocalHosts)
    }

    @MainActor
    @Test func read_whenSettingsHoldValues_thenSnapshotMatches() throws {
        let suite = "beam-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HomePadSettings(defaults: defaults)
        settings.register(BeamSettings.descriptors)
        #expect(BeamPreferences.read(from: settings) == BeamPreferences())

        defaults.set(false, forKey: "beam.receiveBeams")
        defaults.set("openImmediately", forKey: "beam.approvalMode")
        defaults.set("Kitchen", forKey: "beam.hubName")
        defaults.set("Ada", forKey: "beam.companionName")
        defaults.set(false, forKey: "beam.sharePlay")
        defaults.set(false, forKey: "beam.handoff")
        defaults.set(false, forKey: "beam.keepHistory")
        defaults.set(true, forKey: "beam.allowLocalAddresses")
        let read = BeamPreferences.read(from: settings)
        #expect(read == BeamPreferences(
            receiveBeams: false, approvalModeValue: "openImmediately", hubName: "Kitchen", companionName: "Ada",
            sharePlayEnabled: false, handoffEnabled: false, keepHistory: false, allowLocalAddresses: true
        ))
    }
}

@Suite struct BeamDeepLinkTests {
    @Test func parse_whenBeamLink_thenReturnsRawURLTextAndTitle() throws {
        let url = try #require(URL(string: "homepad://beam?url=https%3A%2F%2Fexample.com%2Fa%3Fb%3Dc&title=Soup%0Atime"))
        #expect(try BeamDeepLink.parse(url) == .beam(urlText: "https://example.com/a?b=c", title: "Soup time"))
        let bare = try #require(URL(string: "HOMEPAD://BEAM?url=javascript:alert(1)"))
        #expect(try BeamDeepLink.parse(bare) == .beam(urlText: "javascript:alert(1)", title: nil))
    }

    @Test func parse_whenPairLink_thenReturnsWholeCode() throws {
        let code = Fixture.invitation().invitation.code
        let url = try #require(URL(string: code))
        #expect(try BeamDeepLink.parse(url) == .pair(code: code))
    }

    @Test func parse_whenNotOurs_thenThrowsTyped() throws {
        #expect(throws: BeamDeepLinkError.notHomePadLink) { try BeamDeepLink.parse(try #require(URL(string: "https://example.com/beam?url=x"))) }
        #expect(throws: BeamDeepLinkError.unsupportedAction) { try BeamDeepLink.parse(try #require(URL(string: "homepad://widgets?x=1"))) }
        #expect(throws: BeamDeepLinkError.unsupportedAction) { try BeamDeepLink.parse(try #require(URL(string: "homepad:beam"))) }
        #expect(throws: BeamDeepLinkError.missingURL) { try BeamDeepLink.parse(try #require(URL(string: "homepad://beam"))) }
        #expect(throws: BeamDeepLinkError.missingURL) { try BeamDeepLink.parse(try #require(URL(string: "homepad://beam?url="))) }
        #expect(throws: BeamDeepLinkError.missingURL) { try BeamDeepLink.parse(try #require(URL(string: "homepad://beam?title=x"))) }
    }

    @Test func beamLink_whenBuilt_thenParsesBack() throws {
        let page = try #require(URL(string: "https://example.com/a?b=c&d=e#f"))
        let link = try #require(BeamDeepLink.beamLink(for: page, title: "A & B"))
        #expect(try BeamDeepLink.parse(link) == .beam(urlText: page.absoluteString, title: "A & B"))
        let untitled = try #require(BeamDeepLink.beamLink(for: page, title: " "))
        #expect(try BeamDeepLink.parse(untitled) == .beam(urlText: page.absoluteString, title: nil))
    }
}

@Suite struct HandoffPayloadTests {
    let page = URL(string: "https://example.com/page")

    @Test func parse_whenBeamActivity_thenPrefersUserInfoThenWebpageURL() throws {
        let payload = HandoffPayload(urlText: "https://example.com/a", title: "T\nitle")
        #expect(payload.userInfo == ["url": "https://example.com/a", "title": "T itle"])
        #expect(HandoffPayload(urlText: "x", title: nil).userInfo == ["url": "x"])
        let parsed = try HandoffPayload.parse(activityType: HomePadIdentifiers.beamActivityType, webpageURL: page, userInfo: payload.userInfo)
        #expect(parsed == payload)
        let fallback = try HandoffPayload.parse(activityType: HomePadIdentifiers.beamActivityType, webpageURL: page, userInfo: ["url": 5])
        #expect(fallback == HandoffPayload(urlText: "https://example.com/page", title: nil))
    }

    @Test func parse_whenBrowsingWeb_thenUsesWebpageURL() throws {
        let parsed = try HandoffPayload.parse(activityType: NSUserActivityTypeBrowsingWeb, webpageURL: page, userInfo: ["url": "ignored"])
        #expect(parsed == HandoffPayload(urlText: "https://example.com/page", title: nil))
    }

    @Test func parse_whenURLMissingOrTypeUnknown_thenThrowsTyped() {
        #expect(throws: HandoffError.missingURL) { try HandoffPayload.parse(activityType: HomePadIdentifiers.beamActivityType, webpageURL: nil, userInfo: nil) }
        #expect(throws: HandoffError.missingURL) { try HandoffPayload.parse(activityType: HomePadIdentifiers.beamActivityType, webpageURL: nil, userInfo: ["url": ""]) }
        #expect(throws: HandoffError.missingURL) { try HandoffPayload.parse(activityType: NSUserActivityTypeBrowsingWeb, webpageURL: nil, userInfo: nil) }
        #expect(throws: HandoffError.unsupportedActivityType) { try HandoffPayload.parse(activityType: "com.example.other", webpageURL: page, userInfo: nil) }
    }
}

@Suite struct SharePlayTests {
    @Test(arguments: [
        SharePlayMessage.navigate(urlText: "https://example.com", title: "T", sequence: 3),
        .navigate(urlText: "https://example.com", title: nil, sequence: .max),
        .scroll(fraction: 0.25, sequence: 2),
        .close,
    ])
    func message_whenRoundTripped_thenEqual(message: SharePlayMessage) throws {
        #expect(try JSONDecoder().decode(SharePlayMessage.self, from: JSONEncoder().encode(message)) == message)
    }

    @Test func message_whenVersionOrTypeUnknown_thenThrows() {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SharePlayMessage.self, from: Data(#"{"v":2,"t":"close"}"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SharePlayMessage.self, from: Data(#"{"v":1,"t":"dance"}"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SharePlayMessage.self, from: Data(#"{"v":1,"t":"navigate"}"#.utf8)) }
    }

    @Test func localNavigation_whenNewPage_thenBroadcastsWithNextSequence() {
        var state = SharedBrowsingState()
        #expect(state.catchUpMessage == nil)
        #expect(state.scrollMessage(fraction: 0.5) == nil)
        let message = state.localNavigation(to: "https://example.com/a", title: "A", localParticipant: "p1")
        #expect(message == .navigate(urlText: "https://example.com/a", title: "A", sequence: 1))
        #expect(state.localNavigation(to: "https://example.com/a", title: "A", localParticipant: "p1") == nil)
        #expect(state.localNavigation(to: "https://example.com/b", title: nil, localParticipant: "p1") == .navigate(urlText: "https://example.com/b", title: nil, sequence: 2))
        #expect(state.catchUpMessage == .navigate(urlText: "https://example.com/b", title: nil, sequence: 2))
    }

    @Test func localNavigation_whenURLFailsPolicy_thenNotBroadcast() {
        var state = SharedBrowsingState()
        #expect(state.localNavigation(to: "javascript:alert(1)", title: nil, localParticipant: "p1") == nil)
        #expect(state.localNavigation(to: "http://192.168.0.1", title: nil, localParticipant: "p1") == nil)
        #expect(state.sequence == 0)
    }

    @Test func receive_whenRemoteNavigates_thenLoadsAndDoesNotEchoBack() throws {
        var state = SharedBrowsingState()
        let action = state.receive(.navigate(urlText: "https://example.com/a", title: "A\n", sequence: 4), from: "p2")
        #expect(action == .load(try #require(Fixture.validated("https://example.com/a")), title: "A"))
        #expect(state.sequence == 4)
        #expect(state.localNavigation(to: "https://example.com/a", title: "A", localParticipant: "p1") == nil)
        #expect(state.localNavigation(to: "https://example.com/b", title: nil, localParticipant: "p1") == .navigate(urlText: "https://example.com/b", title: nil, sequence: 5))
    }

    @Test func receive_whenStaleOrUnsafe_thenIgnored() {
        var state = SharedBrowsingState()
        _ = state.receive(.navigate(urlText: "https://example.com/a", title: nil, sequence: 5), from: "p2")
        #expect(state.receive(.navigate(urlText: "https://example.com/old", title: nil, sequence: 4), from: "p3") == nil)
        #expect(state.receive(.navigate(urlText: "javascript:alert(1)", title: nil, sequence: 9), from: "p3") == nil)
        #expect(state.receive(.navigate(urlText: "file:///etc/passwd", title: nil, sequence: 9), from: "p3") == nil)
        #expect(state.current?.url.path == "/a")
        #expect(state.sequence == 5)
    }

    @Test func receive_whenSequenceTies_thenHigherParticipantWinsOnEveryDevice() throws {
        var first = SharedBrowsingState()
        var second = SharedBrowsingState()
        let fromFirst = first.localNavigation(to: "https://example.com/one", title: nil, localParticipant: "p1")
        let fromSecond = second.localNavigation(to: "https://example.com/two", title: nil, localParticipant: "p2")
        guard let fromFirst, let fromSecond else {
            Issue.record("both should broadcast")
            return
        }
        let adopted = first.receive(fromSecond, from: "p2")
        #expect(adopted == .load(try #require(Fixture.validated("https://example.com/two")), title: nil))
        #expect(second.receive(fromFirst, from: "p1") == nil)
        #expect(first.current == second.current)
    }

    @Test func receive_whenSamePageWithNewerSequence_thenAdoptsSequenceWithoutReload() {
        var state = SharedBrowsingState()
        _ = state.localNavigation(to: "https://example.com/a", title: nil, localParticipant: "p1")
        #expect(state.receive(.navigate(urlText: "https://example.com/a", title: nil, sequence: 7), from: "p2") == nil)
        #expect(state.sequence == 7)
    }

    @Test func receive_whenScroll_thenClampedAndOnlyForCurrentPage() {
        var state = SharedBrowsingState()
        #expect(state.receive(.scroll(fraction: 0.5, sequence: 0), from: "p2") == nil)
        _ = state.receive(.navigate(urlText: "https://example.com/a", title: nil, sequence: 2), from: "p2")
        #expect(state.receive(.scroll(fraction: 0.5, sequence: 2), from: "p2") == .scroll(fraction: 0.5))
        #expect(state.receive(.scroll(fraction: 7, sequence: 2), from: "p2") == .scroll(fraction: 1))
        #expect(state.receive(.scroll(fraction: -1, sequence: 2), from: "p2") == .scroll(fraction: 0))
        #expect(state.receive(.scroll(fraction: .nan, sequence: 2), from: "p2") == nil)
        #expect(state.receive(.scroll(fraction: 0.5, sequence: 1), from: "p2") == nil)
        #expect(state.scrollMessage(fraction: 2) == .scroll(fraction: 1, sequence: 2))
        #expect(state.scrollMessage(fraction: .infinity) == nil)
    }

    @Test func receive_whenClose_thenClearsPage() {
        var state = SharedBrowsingState(policy: BeamURLPolicy(allowsLocalHosts: true))
        _ = state.receive(.navigate(urlText: "http://192.168.1.2/", title: "x", sequence: 1), from: "p2")
        #expect(state.current != nil)
        #expect(state.receive(.close, from: "p2") == .close)
        #expect(state.current == nil)
        #expect(state.currentTitle == nil)
        #expect(state.catchUpMessage == nil)
    }
}

@Suite struct ReconnectPolicyTests {
    let policy = ReconnectPolicy()

    @Test func delay_whenAttemptsGrow_thenDoublesUpToCap() {
        #expect(policy.delay(afterAttempt: 1, jitter: 0.5) == 0.5)
        #expect(policy.delay(afterAttempt: 2, jitter: 0.5) == 1)
        #expect(policy.delay(afterAttempt: 3, jitter: 0.5) == 2)
        #expect(policy.delay(afterAttempt: 10, jitter: 0.5) == 8)
        #expect(policy.delay(afterAttempt: 10_000, jitter: 0.5) == 8)
        #expect(policy.delay(afterAttempt: 0, jitter: 0.5) == 0.5)
    }

    @Test func delay_whenJitterVaries_thenStaysWithinFraction() {
        #expect(policy.delay(afterAttempt: 3, jitter: 0) == 1.5)
        #expect(policy.delay(afterAttempt: 3, jitter: 1) == 2.5)
        #expect(policy.delay(afterAttempt: 3, jitter: -4) == 1.5)
        #expect(policy.delay(afterAttempt: 3, jitter: 9) == 2.5)
    }

    @Test func shouldRetry_whenUserInitiated_thenStopsAfterThreeAttempts() {
        #expect(policy.shouldRetry(afterAttempt: 1, userInitiated: true))
        #expect(policy.shouldRetry(afterAttempt: 2, userInitiated: true))
        #expect(!policy.shouldRetry(afterAttempt: 3, userInitiated: true))
        #expect(policy.shouldRetry(afterAttempt: 50, userInitiated: false))
        #expect(ReconnectPolicy(userInitiatedAttempts: 1).shouldRetry(afterAttempt: 1, userInitiated: true) == false)
    }
}

@Suite struct BrowserPolicyTests {
    @Test func choice_whenPersonalContentLocked_thenEphemeral() {
        #expect(BrowserDataStore.choice(isPersonalContentUnlocked: false, activeProfileID: Fixture.profileID) == .ephemeral)
        #expect(BrowserDataStore.choice(isPersonalContentUnlocked: false, activeProfileID: nil) == .ephemeral)
        #expect(BrowserDataStore.choice(isPersonalContentUnlocked: true, activeProfileID: nil) == .ephemeral)
        #expect(BrowserDataStore.choice(isPersonalContentUnlocked: true, activeProfileID: Fixture.profileID) == .profile(Fixture.profileID))
    }

    @Test(arguments: [
        ("https://example.com", true as Bool?, false, BeamNavigationPolicy.Decision.allow),
        ("http://example.com", true, false, .allow),
        ("https://example.com/file.zip", true, true, .cancel),
        ("tel:5551234", true, false, .cancel),
        ("itms-apps://apps.apple.com", true, false, .cancel),
        ("homepad://beam?url=x", true, false, .cancel),
        ("javascript:alert(1)", true, false, .cancel),
        ("data:text/html,hi", true, false, .cancel),
        ("about:blank", false, false, .allow),
        ("blob:https://example.com/1", false, false, .allow),
        ("data:text/html,hi", false, false, .allow),
        ("file:///etc/passwd", false, false, .cancel),
        ("https://example.com/new", nil, false, .loadInPlace),
        ("mailto:a@example.com", nil, false, .cancel),
        ("/relative", true, false, .cancel),
        ("http://192.168.1.1/admin", true, false, .cancel),
        ("http://192.168.1.1/admin", nil, false, .cancel),
        ("https://user:pw@example.com/", true, false, .cancel),
        ("http://192.168.1.1/frame", false, false, .allow),
    ])
    func decide_whenNavigationRequested_thenFollowsOnlyWebContent(text: String, mainFrame: Bool?, download: Bool, expected: BeamNavigationPolicy.Decision) {
        #expect(BeamNavigationPolicy.decide(url: URL(string: text), targetsMainFrame: mainFrame, isDownload: download, policy: BeamURLPolicy()) == expected)
    }

    @Test func decide_whenNoURL_thenCancels() {
        #expect(BeamNavigationPolicy.decide(url: nil, targetsMainFrame: true, isDownload: false, policy: BeamURLPolicy()) == .cancel)
    }

    @Test func decide_whenLocalHostsAllowed_thenFollowsLocalNavigation() throws {
        let local = try #require(URL(string: "http://192.168.1.1/recipes"))
        #expect(BeamNavigationPolicy.decide(url: local, targetsMainFrame: true, isDownload: false, policy: BeamURLPolicy(allowsLocalHosts: true)) == .allow)
    }
}
