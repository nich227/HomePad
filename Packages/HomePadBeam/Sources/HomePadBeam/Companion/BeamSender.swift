import Foundation
import HomePadBeamCore
import HomePadCore
import Observation
import os

public enum CompanionPairingState: Equatable, Sendable {
    case idle
    case pairing
    case paired(PeerDevice)
    case invalidCode(PairingInvitationError)
    case failed(PeerLinkError)
}

/// The companion's side of beaming: finds paired hubs, sends a page, and reports what the hub
/// did with it.
@MainActor
@Observable
public final class BeamSender {
    public private(set) var hubs: [PairedDevice] = []
    public private(set) var delivery: BeamDeliveryState = .idle
    public private(set) var pairingState: CompanionPairingState = .idle
    /// A page the hub sent back to this device.
    public private(set) var incoming: BeamPayload?
    public private(set) var storeError: PairingStoreError?

    public let link: PeerLink
    public var linkStatus: PeerLinkStatus { link.status }
    public var preferences: BeamPreferences { BeamPreferences.read(from: settings) }

    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let store: any PairingStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let log = Logger(subsystem: HomePadIdentifiers.bundlePrefix, category: "beam.sender")
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var receipts: [UUID: BeamReceipt] = [:]
    @ObservationIgnored private var lastBeamID: UUID?
    /// The companion accepts local addresses when typing; whether they open is the hub's choice.
    @ObservationIgnored private let inputPolicy = BeamURLPolicy(allowsLocalHosts: true)

    public init(
        link: PeerLink,
        settings: HomePadSettings,
        store: any PairingStore = KeychainPairingStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.link = link
        self.settings = settings
        self.store = store
        self.now = now
    }

    /// Starts consuming the link. Call once, after creating the sender.
    public func start() {
        guard tasks.isEmpty else { return }
        reloadHubs()
        let messages = link.decoded(BeamMessage.self, on: PeerChannelName.beam)
        tasks.append(Task { [weak self] in
            for await (_, message) in messages {
                self?.received(message)
            }
        })
    }

    /// Looks for hubs only while the app, or the share sheet, is on screen.
    public func setSceneActive(_ active: Bool) {
        if active { reloadHubs() }
        Task { [link] in await link.setBrowsing(active) }
    }

    public func isReachable(_ hubID: UUID) -> Bool {
        linkStatus.snapshot.visibleHubs.contains { $0.hubID == hubID }
    }

    /// Checks what was typed or shared, without sending.
    public func validate(_ text: String) -> Result<ValidatedURL, BeamURLRejection> {
        inputPolicy.validate(BeamURLPolicy.normalizedUserInput(text))
    }

    /// Sends a page to a hub. Tries the connection up to three times, then waits a few seconds
    /// for the hub to say what it did.
    @discardableResult
    public func send(_ text: String, title: String?, to hubID: UUID?, kind: BeamKind = .website) async -> BeamDeliveryState {
        let url: ValidatedURL
        switch validate(text) {
        case .success(let validated): url = validated
        case .failure(let reason): return finish(.failed(.invalidURL(reason)))
        }
        guard let hub = hubs.first(where: { $0.id == hubID }) ?? (hubs.count == 1 ? hubs.first : nil) else {
            return finish(.failed(.noPairedHub))
        }
        delivery = .sending
        let beam = BeamPayload(id: UUID(), url: url.url, title: title, sender: link.localDevice, sentAt: now(), kind: kind)
        lastBeamID = beam.id
        do {
            try await link.connect(to: hub.id, userInitiated: true)
            try await link.send(BeamMessage(.beam(beam)), on: PeerChannelName.beam, to: hub.id)
        } catch {
            log.notice("Could not reach the hub")
            return finish(.failed(.hubUnreachable))
        }
        let deadline = now().addingTimeInterval(BeamDeliveryState.receiptTimeout)
        while receipts[beam.id] == nil, now() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let receipt = receipts.removeValue(forKey: beam.id) else {
            return finish(.failed(.noReceipt))
        }
        return finish(.delivered(receipt.outcome))
    }

    public func resetDelivery() {
        delivery = .idle
    }

    // MARK: Pairing

    /// Pairs with the hub whose QR code produced `code`.
    public func pair(code: String) async {
        let invitation: PairingInvitation
        do {
            invitation = try PairingInvitation.parse(code, now: now())
        } catch {
            pairingState = .invalidCode(error)
            return
        }
        pairingState = .pairing
        do {
            let record = try await link.pair(using: invitation)
            pairingState = .paired(record.device)
        } catch {
            pairingState = .failed(error)
        }
        reloadHubs()
    }

    public func resetPairing() {
        pairingState = .idle
    }

    public func forget(_ hubID: UUID) {
        Task { [weak self, link] in
            do {
                try await link.forget(hubID: hubID)
            } catch {
                self?.log.error("Could not remove a hub")
            }
            self?.reloadHubs()
        }
    }

    /// Handles `homepad://pair?c=...`, which the Camera app opens after scanning the hub's code.
    /// Returns false for links this package does not own.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard case .pair(let code) = try? BeamDeepLink.parse(url) else { return false }
        Task { await pair(code: code) }
        return true
    }

    public func dismissIncoming() {
        incoming = nil
    }

    // MARK: Private

    private func received(_ message: BeamMessage) {
        switch message.content {
        case .receipt(let receipt):
            receipts[receipt.beamID] = receipt
            if let lastBeamID {
                delivery = delivery.applying(receipt, to: lastBeamID)
            }
        case .beam(let beam):
            // Only an authenticated hub can reach this point; the address is still checked.
            guard case .success = inputPolicy.validate(beam.url) else { return }
            incoming = beam
        }
    }

    private func finish(_ state: BeamDeliveryState) -> BeamDeliveryState {
        delivery = state
        return state
    }

    private func reloadHubs() {
        do {
            hubs = try store.devices().filter { $0.device.role == .hub }
            storeError = nil
        } catch {
            hubs = []
            storeError = error
        }
    }
}
