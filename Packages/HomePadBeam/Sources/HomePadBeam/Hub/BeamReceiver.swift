import Foundation
import HomePadBeamCore
import HomePadCore
import Observation
import os

/// The hub's side of beaming: takes pages from the peer link, SharePlay, Handoff, and deep links,
/// runs each through the URL and approval policies, and keeps the browser session of whoever is
/// in front of the hub.
///
/// Everything this type publishes about pages is for the person `HouseholdSession` says is
/// active at the moment it is read. A page that belongs to someone else is held unseen until
/// its owner is in front, and every page a person has open closes when they sign out, which is
/// when `HouseholdSession.audienceGeneration` changes. A person the camera merely lost sight of
/// has not signed out: their pages stay open and on screen until the household session's grace
/// period ends.
@MainActor
@Observable
public final class BeamReceiver {
    public private(set) var pairedDevices: [PairedDevice] = []
    /// The pairing invitation on screen, if pairing mode is open.
    public private(set) var invitation: PairingInvitation?
    /// The device that completed the most recent pairing, for the success state.
    public private(set) var lastPairedDevice: PairedDevice?
    public private(set) var storeError: PairingStoreError?

    public let link: PeerLink
    public var linkStatus: PeerLinkStatus { link.status }
    public var preferences: BeamPreferences { BeamPreferences.read(from: settings) }

    @ObservationIgnored private let session: HouseholdSession
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let store: any PairingStore
    @ObservationIgnored private let random: any RandomSource
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let log = Logger(subsystem: HomePadIdentifiers.bundlePrefix, category: "beam.receiver")
    /// Called when someone signs out, after their pages have closed.
    @ObservationIgnored public var onSignOut: ((BrowserOwner) -> Void)?

    private var intake = BeamIntake()
    @ObservationIgnored private let pageStore = BeamPageStore()
    @ObservationIgnored private var sharedPageID: UUID?
    @ObservationIgnored private var unannouncedSignOut: BrowserOwner?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var pairingSession = PairingSession()
    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var configurationTask: Task<Void, Never>?
    @ObservationIgnored private var needsConfiguration = false

    public init(
        link: PeerLink,
        session: HouseholdSession,
        settings: HomePadSettings,
        store: any PairingStore = KeychainPairingStore(),
        random: any RandomSource = SystemRandomSource(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.link = link
        self.session = session
        self.settings = settings
        self.store = store
        self.random = random
        self.now = now
    }

    /// Starts consuming the link. Call once, after creating the receiver.
    public func start() {
        guard tasks.isEmpty else { return }
        reloadPairedDevices()
        let beams = link.decoded(BeamMessage.self, on: PeerChannelName.beam)
        tasks.append(Task { [weak self] in
            for await (sender, message) in beams {
                self?.received(message, from: sender)
            }
        })
        let events = link.events
        tasks.append(Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        })
        observeSettings()
        observeSession()
        flush()
    }

    /// The listener runs only while the hub's scene is active. Call from the scene phase handler.
    public func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if active {
            reloadPairedDevices()
            refreshPairing()
        }
        configureLink()
    }

    /// Household members whose paired iPhone is connected right now. The app can feed this to
    /// `HouseholdSession.setCompanionPresent`.
    public var connectedProfileIDs: Set<UUID> {
        Set(linkStatus.snapshot.connectedPeers.compactMap(\.profileID))
    }

    // MARK: Pairing

    /// Opens pairing mode and returns the invitation to show as a QR code. The new device will
    /// belong to `profileID`.
    @discardableResult
    public func openPairing(for profileID: UUID?) -> PairingInvitation? {
        lastPairedDevice = nil
        do {
            invitation = try pairingSession.open(
                hubID: link.localDevice.id,
                hubName: preferences.hubName,
                profileID: profileID,
                now: now(),
                random: random
            )
        } catch {
            log.error("Could not create a pairing secret")
            invitation = nil
        }
        configureLink()
        return invitation
    }

    public func closePairing() {
        pairingSession.close()
        invitation = nil
        configureLink()
    }

    public func pairingSecondsRemaining(at date: Date) -> Int {
        pairingSession.secondsRemaining(at: date)
    }

    /// Clears an invitation that has run out. The view calls this as its countdown ticks.
    public func refreshPairing() {
        guard invitation != nil, pairingSession.active(at: now()) == nil else { return }
        closePairing()
    }

    public func revoke(_ deviceID: UUID) {
        intake.forget(deviceID: deviceID)
        flush()
        Task { [weak self, link] in
            do {
                try await link.revoke(deviceID: deviceID)
            } catch {
                self?.log.error("Could not revoke a paired device")
            }
            self?.reloadPairedDevices()
            self?.configureLink()
        }
    }

    // MARK: The browser of the person in front

    /// The person in front of the hub, read from the household session each time.
    public var viewer: BrowserOwner {
        BrowserOwner(activeProfileID: session.activeProfile?.id)
    }

    /// The open pages of the person in front of the hub. Oldest first.
    public var pages: [BrowserPage] {
        intake.browser.pages(for: viewer)
    }

    public var frontPage: BrowserPage? {
        intake.browser.frontPage(for: viewer)
    }

    /// The beam the hub should put on screen for the person in front of it: a recipe that was
    /// just opened, or the page in front while the browser asks for the screen. `nil` when
    /// there is nothing to show or the browser was put away with `closeBrowser()`.
    public var current: ApprovedBeam? {
        intake.browser.presented(for: viewer)
    }

    /// Beams the hub is asking the person in front of it about. Oldest first. A beam that
    /// belongs to someone else is never in this list.
    public var pending: [BeamPayload] {
        intake.offers(for: viewer)
    }

    /// Pages the person in front of the hub opened recently. Newest first. Kept in memory only.
    public var recents: [BeamPayload] {
        intake.browser.recents(for: viewer)
    }

    /// The web page behind an open page of the person in front of the hub.
    func model(for pageID: UUID) -> BeamBrowserModel? {
        guard pages.contains(where: { $0.id == pageID }) else { return nil }
        return pageStore.model(for: pageID)
    }

    public func approve(_ id: UUID) {
        syncPresence()
        if let approved = intake.approve(id: id, preferences: preferences, dataStore: dataStoreForNewPage, now: now()),
           case .peerLink(let deviceID) = approved.source {
            noteApproval(from: deviceID)
        }
        flush()
    }

    public func decline(_ id: UUID) {
        syncPresence()
        intake.decline(id: id)
        flush()
    }

    /// Opens a page from the recents of the person in front of the hub.
    public func reopen(_ beam: BeamPayload) {
        syncPresence()
        _ = intake.reopen(recentID: beam.id, preferences: preferences, dataStore: dataStoreForNewPage, now: now())
        flush()
    }

    public func selectPage(_ pageID: UUID) {
        syncPresence()
        intake.selectPage(pageID)
        flush()
    }

    public func closePage(_ pageID: UUID) {
        syncPresence()
        intake.closePage(pageID)
        flush()
    }

    public func closeAllPages() {
        syncPresence()
        intake.closeAllPages()
        flush()
    }

    /// Takes the browser off the screen, so `current` becomes `nil`, and ends a recipe hand-off.
    /// Open pages stay open until the person closes them or signs out.
    public func closeBrowser() {
        syncPresence()
        intake.putAway()
        flush()
    }

    /// The companion a page can be sent back to: the iPhone that beamed the page in front, or
    /// the connected iPhone of the member whose session it is.
    public var sendBackTarget: PeerDevice? {
        SendBackPolicy.target(
            pageSource: frontPage?.beam.source,
            owner: viewer,
            connected: linkStatus.snapshot.connectedPeers
        )
    }

    /// Sends the page the hub is showing to a companion. Returns whether it was written to the link.
    public func sendBack(_ url: URL, title: String?) async -> Bool {
        guard let target = sendBackTarget, case .success(let validated) = preferences.urlPolicy.validate(url) else {
            return false
        }
        let beam = BeamPayload(id: UUID(), url: validated.url, title: title, sender: link.localDevice, sentAt: now())
        do {
            try await link.send(BeamMessage(.beam(beam)), on: PeerChannelName.beam, to: target.id)
            return true
        } catch {
            log.notice("Could not send the page back to the companion")
            return false
        }
    }

    // MARK: Other paths

    /// Handles `homepad://beam?url=...`. Returns false for links this package does not own.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard case .beam(let text, let title) = try? BeamDeepLink.parse(url) else { return false }
        accept(urlText: text, title: title, source: .deepLink)
        return true
    }

    /// Handles a Handoff activity: this app's beam activity or the system web browsing activity.
    @discardableResult
    public func handle(userActivity: NSUserActivity) -> Bool {
        guard preferences.handoffEnabled,
              let payload = try? HandoffPayload.parse(
                  activityType: userActivity.activityType,
                  webpageURL: userActivity.webpageURL,
                  userInfo: userActivity.userInfo
              )
        else { return false }
        accept(urlText: payload.urlText, title: payload.title, source: .handoff)
        return true
    }

    /// Shows a page that a SharePlay session navigated to. The session has one page on the hub:
    /// it opens as a new page for the person in front, and later navigations load in it and
    /// bring it to the front. The URL has already passed the policy.
    public func open(sharePlay url: ValidatedURL, title: String?) {
        syncPresence()
        if let sharedPageID, let model = model(for: sharedPageID) {
            if model.url != url.url { model.load(url) }
            intake.selectPage(sharedPageID)
            flush()
        } else {
            sharedPageID = accept(urlText: url.url.absoluteString, title: title, source: .sharePlay)
        }
    }

    /// Closes the page a SharePlay session opened, when the session's page is closed.
    public func closeSharedPage() {
        guard let sharedPageID else { return }
        self.sharedPageID = nil
        closePage(sharedPageID)
    }

    // MARK: Private

    private func received(_ message: BeamMessage, from sender: UUID) {
        guard case .beam(let claimed) = message.content else { return }
        guard let record = pairedDevices.first(where: { $0.id == sender }) ?? reloadedRecord(sender) else {
            log.notice("Dropped a beam from a device with no pairing record")
            return
        }
        syncPresence()
        _ = intake.receive(
            claimed.attributed(to: record.device),
            source: .peerLink(deviceID: sender),
            senderProfileID: record.device.profileID,
            householdProfileIDs: Set(session.profiles.map(\.id)),
            preferences: preferences,
            senderApprovedBeamCount: record.approvedBeamCount,
            dataStore: dataStoreForNewPage,
            now: now()
        )
        flush()
    }

    /// Takes a page that started at the hub. Returns its ID when it opened as a page.
    @discardableResult
    private func accept(urlText: String, title: String?, source: BeamSource) -> UUID? {
        guard let url = URL(string: urlText) else { return nil }
        syncPresence()
        let beam = BeamPayload(id: UUID(), url: url, title: title, sender: link.localDevice, sentAt: now())
        let result = intake.receive(
            beam,
            source: source,
            senderProfileID: nil,
            householdProfileIDs: Set(session.profiles.map(\.id)),
            preferences: preferences,
            senderApprovedBeamCount: 0,
            dataStore: dataStoreForNewPage,
            now: now()
        )
        flush()
        guard case .open(let approved) = result, pages.contains(where: { $0.id == approved.id }) else { return nil }
        return approved.id
    }

    private func openChildPage(of parentID: UUID, url: ValidatedURL) {
        syncPresence()
        _ = intake.openChildPage(of: parentID, url: url, id: UUID(), now: now())
        flush()
    }

    /// Tells the intake who is in front of the hub. Every entry point calls this first, so a
    /// decision is never made for someone who has already left.
    private func syncPresence() {
        let presence = HubPresence(activeProfileID: session.activeProfile?.id, audienceGeneration: session.audienceGeneration)
        guard presence != intake.browser.presence else { return }
        let devices = pairedDevices
        let signOut = intake.presenceChanged(
            to: presence,
            preferences: preferences,
            approvedBeamCount: { id in devices.first { $0.id == id }?.approvedBeamCount ?? 0 },
            dataStore: dataStoreForNewPage,
            now: now()
        )
        if let signOut {
            sharedPageID = nil
            unannouncedSignOut = signOut.owner
            log.info("Closed \(signOut.closedPageIDs.count) pages at sign out")
        }
    }

    /// The jar a page gets if it opens now. A persistent one only while the active member's
    /// personal content is unlocked. A page keeps the jar it opened with until it closes.
    private var dataStoreForNewPage: BrowserDataStore {
        BrowserDataStore.choice(
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            activeProfileID: session.activeProfile?.id
        )
    }

    /// Carries out what the intake decided: answers the senders, makes the web pages match the
    /// open pages, and comes back when the next held beam runs out.
    private func flush() {
        syncPresence()
        for notice in intake.takeReceipts() {
            sendReceipt(notice.receipt, to: notice.deviceID)
        }
        pageStore.sync(
            pages: intake.browser.pages(for: intake.active),
            policy: preferences.urlPolicy,
            onNewPage: { [weak self] parentID, url in self?.openChildPage(of: parentID, url: url) }
        )
        if let owner = unannouncedSignOut {
            unannouncedSignOut = nil
            onSignOut?(owner)
        }
        expiryTask?.cancel()
        guard let next = intake.nextExpiry else { return }
        let delay = max(0, next.timeIntervalSince(now())) + 1
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.intake.pruneExpired(now: self.now())
            self.flush()
        }
    }

    /// Follows the household session. A sign out, or a change of the active person, reaches the
    /// browser on the next main actor turn.
    private func observeSession() {
        withObservationTracking {
            _ = session.activeProfile?.id
            _ = session.audienceGeneration
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.flush()
                self?.observeSession()
            }
        }
    }

    private func handle(_ event: PeerLinkEvent) {
        switch event {
        case .paired(let record):
            pairingSession.close()
            invitation = nil
            lastPairedDevice = record
            reloadPairedDevices()
            configureLink()
        case .peerConnected, .peerDisconnected:
            break
        }
    }

    private func noteApproval(from deviceID: UUID) {
        guard var record = pairedDevices.first(where: { $0.id == deviceID }) else { return }
        record.approvedBeamCount += 1
        do {
            try store.save(record)
            storeError = nil
        } catch {
            storeError = error
        }
        reloadPairedDevices()
    }

    private func sendReceipt(_ receipt: BeamReceipt, to deviceID: UUID) {
        Task { [link, log] in
            do {
                try await link.send(BeamMessage(.receipt(receipt)), on: PeerChannelName.beam, to: deviceID)
            } catch {
                log.debug("Receipt not delivered; the sender is no longer connected")
            }
        }
    }

    private func reloadedRecord(_ deviceID: UUID) -> PairedDevice? {
        reloadPairedDevices()
        return pairedDevices.first { $0.id == deviceID }
    }

    private func reloadPairedDevices() {
        do {
            pairedDevices = try store.devices()
            storeError = nil
        } catch {
            pairedDevices = []
            storeError = error
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = preferences
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.configureLink()
                self?.observeSettings()
            }
        }
    }

    /// Pushes the current scene, preference, and pairing state to the link. Calls are applied one
    /// at a time and in order.
    private func configureLink() {
        intake.applyHistoryPreference(keepHistory: preferences.keepHistory)
        intake.pruneExpired(now: now())
        flush()
        needsConfiguration = true
        guard configurationTask == nil else { return }
        configurationTask = Task { [weak self] in
            while let self, self.needsConfiguration {
                self.needsConfiguration = false
                let preferences = self.preferences
                await self.link.configureHub(
                    sceneActive: self.isSceneActive,
                    receiveEnabled: preferences.receiveBeams,
                    hubName: preferences.hubName,
                    invitation: self.pairingSession.active(at: self.now())
                )
            }
            self?.configurationTask = nil
        }
    }
}
