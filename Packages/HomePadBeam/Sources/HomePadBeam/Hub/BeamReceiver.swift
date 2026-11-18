import Foundation
import HomePadBeamCore
import HomePadCore
import Observation
import os

/// The hub's side of beaming: takes pages from the peer link, SharePlay, Handoff, and deep links,
/// runs each through the URL and approval policies, and publishes what the hub should show.
@MainActor
@Observable
public final class BeamReceiver {
    /// Beams waiting for someone at the hub to decide. Oldest first.
    public private(set) var pending: [BeamPayload] = []
    /// Pages opened recently. Newest first. Kept in memory only.
    public private(set) var recents: [BeamPayload] = []
    /// The page the hub's browser should be showing.
    public private(set) var current: ApprovedBeam?
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
    @ObservationIgnored private var intake = BeamIntake()
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
        publishInbox()
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

    // MARK: Beams

    public func approve(_ id: UUID) {
        guard let approved = intake.approve(id: id, preferences: preferences) else {
            publishInbox()
            return
        }
        if case .peerLink(let deviceID) = approved.source {
            noteApproval(from: deviceID)
            sendReceipt(BeamReceipt(beamID: id, outcome: .opened), to: deviceID)
        }
        current = approved
        publishInbox()
    }

    public func decline(_ id: UUID) {
        if let declined = intake.decline(id: id), case .peerLink(let deviceID) = declined.source {
            sendReceipt(BeamReceipt(beamID: id, outcome: .declined), to: deviceID)
        }
        publishInbox()
    }

    public func reopen(_ beam: BeamPayload) {
        current = intake.reopen(beam, preferences: preferences)
        publishInbox()
    }

    public func closeBrowser() {
        current = nil
    }

    /// The companion a page can be sent back to: the device that beamed the current page, or
    /// the active profile's paired device, when it is connected.
    public var sendBackTarget: PeerDevice? {
        let connected = linkStatus.snapshot.connectedPeers
        if case .peerLink(let deviceID) = current?.source, let device = connected.first(where: { $0.id == deviceID }) {
            return device
        }
        guard let profileID = session.activeProfile?.id else { return nil }
        return connected.first { $0.profileID == profileID }
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

    /// Opens a page that a SharePlay session navigated to. The URL has already passed the policy.
    public func open(sharePlay url: ValidatedURL, title: String?) {
        accept(urlText: url.url.absoluteString, title: title, source: .sharePlay)
    }

    // MARK: Private

    private func received(_ message: BeamMessage, from sender: UUID) {
        guard case .beam(let claimed) = message.content else { return }
        guard let record = pairedDevices.first(where: { $0.id == sender }) ?? reloadedRecord(sender) else {
            log.notice("Dropped a beam from a device with no pairing record")
            return
        }
        let beam = claimed.attributed(to: record.device)
        let result = intake.receive(
            beam,
            source: .peerLink(deviceID: sender),
            preferences: preferences,
            isGuest: session.isGuest,
            senderApprovedBeamCount: record.approvedBeamCount,
            now: now()
        )
        if case .open(let approved) = result {
            current = approved
        }
        publishInbox()
        sendReceipt(BeamReceipt(beamID: beam.id, outcome: result.outcome), to: sender)
    }

    private func accept(urlText: String, title: String?, source: BeamSource) {
        guard let url = URL(string: urlText) else { return }
        let beam = BeamPayload(id: UUID(), url: url, title: title, sender: link.localDevice, sentAt: now())
        let result = intake.receive(
            beam,
            source: source,
            preferences: preferences,
            isGuest: session.isGuest,
            senderApprovedBeamCount: 0,
            now: now()
        )
        if case .open(let approved) = result {
            current = approved
        }
        publishInbox()
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

    private func publishInbox() {
        pending = intake.inbox.pending
        recents = intake.inbox.history
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
        publishInbox()
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
