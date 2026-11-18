import Foundation
import HomePadBeamCore
import HomePadCore
import Network
import Observation
import os

public enum PeerLinkError: Error, Equatable, Sendable {
    case wrongRole
    case notPaired
    case hubNotFound
    case connectionFailed
    case handshakeRejected
    case invalidMessage
    case storeFailed(PairingStoreError)
}

public enum PeerLinkEvent: Equatable, Sendable {
    /// A pairing completed. On the hub the record holds the companion; on a companion, the hub.
    case paired(PairedDevice)
    case peerConnected(PeerDevice)
    case peerDisconnected(UUID)
}

public struct PeerLinkSnapshot: Equatable, Sendable {
    /// The hub's listening socket is open.
    public var isListening = false
    public var isBrowsing = false
    public var connectedPeers: [PeerDevice] = []
    /// Hubs currently advertised on the local network, paired or not.
    public var visibleHubs: [HubAdvertisement] = []
    /// The person declined the local network permission prompt.
    public var isLocalNetworkDenied = false

    public init() {}
}

/// Connection state for the user interface.
@MainActor
@Observable
public final class PeerLinkStatus {
    public private(set) var snapshot = PeerLinkSnapshot()

    nonisolated init(updates: AsyncStream<PeerLinkSnapshot>) {
        Task { @MainActor [weak self] in
            for await snapshot in updates {
                guard let self else { return }
                self.snapshot = snapshot
            }
        }
    }
}

/// The authenticated transport between a hub and its paired companions.
///
/// The hub listens with one TLS pre-shared key per paired device. A companion connects with the
/// key from its pairing. A connection is handed to this type's logic only after the TLS
/// handshake succeeds, and it carries nothing to subscribers until its hello has been checked.
public actor PeerLink: PeerChannel {
    public nonisolated let localDevice: PeerDevice
    public nonisolated let status: PeerLinkStatus
    /// Pairing and connection changes. One consumer.
    public nonisolated let events: AsyncStream<PeerLinkEvent>

    private nonisolated let queue: DispatchSerialQueue
    private nonisolated let fanout = EnvelopeFanout()
    private nonisolated let eventContinuation: AsyncStream<PeerLinkEvent>.Continuation
    private nonisolated let statusContinuation: AsyncStream<PeerLinkSnapshot>.Continuation
    private nonisolated let log = Logger(subsystem: HomePadIdentifiers.bundlePrefix, category: "beam.link")

    private let store: any PairingStore
    private let now: @Sendable () -> Date
    private let reconnectPolicy: ReconnectPolicy

    private var links: [UUID: Link] = [:]
    private var snapshot = PeerLinkSnapshot()

    // Hub
    private var listener: NWListener?
    private var listenerGeneration = 0
    private var plan: ListenerPlan?
    private var paired: [UUID: PairedDevice] = [:]
    private var hubConfiguration = HubConfiguration()
    private var invitation: PendingInvitation?
    private var invitationTimer: Task<Void, Never>?

    // Companion
    private var browser: NWBrowser?
    private var discovered: [UUID: DiscoveredHub] = [:]
    private var connecting: [UUID: Task<Result<PeerDevice, PeerLinkError>, Never>] = [:]

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    public init(
        localDevice: PeerDevice,
        store: any PairingStore,
        reconnectPolicy: ReconnectPolicy = ReconnectPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.localDevice = localDevice
        self.store = store
        self.reconnectPolicy = reconnectPolicy
        self.now = now
        self.queue = DispatchSerialQueue(label: "\(HomePadIdentifiers.bundlePrefix).beam.link")
        let (events, eventContinuation) = AsyncStream<PeerLinkEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.events = events
        self.eventContinuation = eventContinuation
        let (updates, statusContinuation) = AsyncStream<PeerLinkSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.statusContinuation = statusContinuation
        self.status = PeerLinkStatus(updates: updates)
    }

    // MARK: PeerChannel

    public func connectedPeers() async -> [PeerDevice] {
        establishedPeers()
    }

    public func send(_ payload: Data, on channel: String, to peer: UUID?) async throws {
        let frame: Data
        do {
            frame = try LinkSession.frame(.envelope(channel: channel, payload: payload))
        } catch {
            throw PeerLinkError.invalidMessage
        }
        let targets = links.values.filter { link in
            guard let device = link.peer else { return false }
            return peer == nil || device.id == peer
        }
        if targets.isEmpty {
            if let peer { throw PeerChannelError.unknownPeer(peer) }
            throw PeerChannelError.notConnected
        }
        for link in targets {
            try await write(frame, to: link.connection)
        }
    }

    public nonisolated func messages(on channel: String) -> AsyncStream<PeerEnvelope> {
        fanout.subscribe(to: channel)
    }

    // MARK: Hub

    /// Tells the hub what it may do right now. The listening socket exists only while the scene
    /// is active and there is at least one key to accept: a paired device with receiving on, or
    /// an open pairing invitation.
    public func configureHub(sceneActive: Bool, receiveEnabled: Bool, hubName: String, invitation: PendingInvitation?) {
        guard localDevice.role == .hub else { return }
        hubConfiguration = HubConfiguration(sceneActive: sceneActive, receiveEnabled: receiveEnabled, hubName: hubName)
        self.invitation = invitation
        invitationTimer?.cancel()
        invitationTimer = nil
        if let invitation {
            let delay = max(invitation.invitation.expiresAt.timeIntervalSince(now()), 0)
            invitationTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay + 0.5))
                guard !Task.isCancelled else { return }
                await self?.applyHubPlan()
            }
        }
        applyHubPlan()
    }

    /// Removes a paired device. Its key leaves the listener, so its next TLS handshake fails, and
    /// its open connection is closed. Other devices are not affected.
    public func revoke(deviceID: UUID) throws(PeerLinkError) {
        guard localDevice.role == .hub else { throw .wrongRole }
        do {
            try store.remove(id: deviceID)
        } catch {
            throw .storeFailed(error)
        }
        applyHubPlan()
    }

    private func applyHubPlan() {
        do {
            paired = Dictionary(try store.devices().map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            log.error("Pairing store unavailable; closing the hub link")
            paired = [:]
        }
        let next = ListenerPlan.make(
            sceneActive: hubConfiguration.sceneActive,
            receiveEnabled: hubConfiguration.receiveEnabled,
            hubID: localDevice.id,
            hubName: hubConfiguration.hubName,
            paired: Array(paired.values),
            invitation: invitation,
            now: now()
        )
        for link in Array(links.values) {
            guard let device = link.peer else {
                if next == nil { close(link, sending: .shuttingDown, error: .connectionFailed) }
                continue
            }
            if next == nil || !hubConfiguration.receiveEnabled {
                close(link, sending: .shuttingDown, error: .connectionFailed)
            } else if paired[device.id]?.keys != link.keys {
                close(link, sending: .revoked, error: .handshakeRejected)
            }
        }
        guard next != plan else { return }
        plan = next
        restartListener()
    }

    private func restartListener() {
        listener?.cancel()
        listener = nil
        listenerGeneration += 1
        snapshot.isListening = false
        defer { publish() }
        guard let plan, let parameters = LinkTLS.parameters(credentials: plan.credentials) else { return }
        parameters.acceptLocalOnly = true
        let generation = listenerGeneration
        do {
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: plan.advertisement.name,
                type: HomePadIdentifiers.bonjourServiceType,
                txtRecord: NWTXTRecord(plan.advertisement.txtRecord)
            )
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                self.assumeIsolated { $0.accept(connection, generation: generation) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.assumeIsolated { $0.listenerStateChanged(state, generation: generation) }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            log.error("Could not create the hub listener")
        }
    }

    private func listenerStateChanged(_ state: NWListener.State, generation: Int) {
        guard generation == listenerGeneration else { return }
        switch state {
        case .ready:
            snapshot.isListening = true
        case .failed, .cancelled:
            snapshot.isListening = false
            listener = nil
        case .waiting(let error):
            snapshot.isListening = false
            snapshot.isLocalNetworkDenied = Self.isPolicyDenied(error)
        default:
            break
        }
        publish()
    }

    private func accept(_ connection: NWConnection, generation: Int) {
        let unauthenticated = links.values.count { $0.peer == nil }
        guard generation == listenerGeneration, plan != nil,
              LinkLimits.canAccept(total: links.count, unauthenticated: unauthenticated)
        else {
            connection.cancel()
            return
        }
        start(Link(connection: connection, outbound: nil))
    }

    private func admit(_ hello: LinkHello, on link: Link) {
        let result = HubAuthenticator.admit(
            hello: hello,
            hubID: localDevice.id,
            paired: Array(paired.values),
            invitation: invitation,
            now: now()
        )
        guard case .success(let admission) = result else {
            log.notice("Rejected a hello from a device that is not paired")
            close(link, sending: .unauthorized, error: .handshakeRejected)
            return
        }
        let record = admission.record
        if case .newlyPaired = admission {
            do {
                try store.save(record)
            } catch {
                log.error("Could not save a new pairing")
                close(link, sending: .unauthorized, error: .storeFailed(error))
                return
            }
            invitation = nil
            invitationTimer?.cancel()
            invitationTimer = nil
        }
        paired[record.id] = record
        for other in Array(links.values) where other.id != link.id && other.peer?.id == record.id {
            close(other, sending: .replaced, error: .connectionFailed)
        }
        let hub = PeerDevice(id: localDevice.id, name: hubConfiguration.hubName, role: .hub)
        guard let reply = try? LinkSession.frame(.hello(HubAuthenticator.hello(hub: hub, keys: record.keys))) else {
            close(link, sending: nil, error: .invalidMessage)
            return
        }
        link.connection.send(content: reply, completion: .contentProcessed { _ in })
        link.keys = record.keys
        established(link, peer: record.device)
        if case .newlyPaired = admission {
            eventContinuation.yield(.paired(record))
        }
    }

    // MARK: Companion

    /// Starts or stops looking for hubs. While on, the link connects to every paired hub it sees.
    public func setBrowsing(_ active: Bool) {
        guard localDevice.role == .companion else { return }
        if active {
            startBrowser()
        } else {
            browser?.cancel()
            browser = nil
            discovered = [:]
            snapshot.isBrowsing = false
            snapshot.visibleHubs = []
            for link in Array(links.values) {
                close(link, sending: .shuttingDown, error: .connectionFailed)
            }
            publish()
        }
    }

    /// Connects to a paired hub. A user-initiated call makes at most the number of tries the
    /// reconnect policy allows and then throws.
    @discardableResult
    public func connect(to hubID: UUID, userInitiated: Bool = true) async throws(PeerLinkError) -> PeerDevice {
        guard localDevice.role == .companion else { throw .wrongRole }
        let record: PairedDevice?
        do {
            record = try store.device(id: hubID)
        } catch {
            throw .storeFailed(error)
        }
        guard let record else { throw .notPaired }
        return try await establish(hubID: hubID, keys: record.keys, userInitiated: userInitiated)
    }

    /// Completes a pairing from a scanned invitation and stores it.
    public func pair(using invitation: PairingInvitation) async throws(PeerLinkError) -> PairedDevice {
        guard localDevice.role == .companion else { throw .wrongRole }
        for link in Array(links.values) where link.outbound?.hubID == invitation.hubID {
            close(link, sending: .normal, error: .notPaired)
        }
        let hub = try await establish(hubID: invitation.hubID, keys: invitation.keys, userInitiated: true)
        let record = PairedDevice(device: hub, secret: invitation.secret, hubID: invitation.hubID, pairedAt: now())
        do {
            try store.save(record)
        } catch {
            for link in Array(links.values) where link.peer?.id == hub.id {
                close(link, sending: .normal, error: .connectionFailed)
            }
            throw .storeFailed(error)
        }
        eventContinuation.yield(.paired(record))
        return record
    }

    /// Forgets a hub on this companion.
    public func forget(hubID: UUID) throws(PeerLinkError) {
        guard localDevice.role == .companion else { throw .wrongRole }
        do {
            try store.remove(id: hubID)
        } catch {
            throw .storeFailed(error)
        }
        for link in Array(links.values) where link.outbound?.hubID == hubID {
            close(link, sending: .normal, error: .notPaired)
        }
    }

    private func establish(hubID: UUID, keys: LinkKeys, userInitiated: Bool) async throws(PeerLinkError) -> PeerDevice {
        if let peer = links.values.first(where: { $0.peer?.id == hubID && $0.keys == keys })?.peer {
            return peer
        }
        if let inFlight = connecting[hubID] {
            return try await inFlight.value.get()
        }
        let task = Task { await self.runAttempts(hubID: hubID, keys: keys, userInitiated: userInitiated) }
        connecting[hubID] = task
        let result = await task.value
        connecting[hubID] = nil
        return try result.get()
    }

    private func runAttempts(hubID: UUID, keys: LinkKeys, userInitiated: Bool) async -> Result<PeerDevice, PeerLinkError> {
        var attempt = 0
        while true {
            attempt += 1
            let result = await attemptOnce(hubID: hubID, keys: keys)
            guard case .failure = result else { return result }
            let mayRetry = reconnectPolicy.shouldRetry(afterAttempt: attempt, userInitiated: userInitiated)
                && (userInitiated || attempt < Self.backgroundAttemptLimit)
            guard mayRetry, !Task.isCancelled else { return result }
            let delay = reconnectPolicy.delay(afterAttempt: attempt, jitter: Double.random(in: 0..<1))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func attemptOnce(hubID: UUID, keys: LinkKeys) async -> Result<PeerDevice, PeerLinkError> {
        startBrowser()
        var endpoint = discovered[hubID]?.endpoint
        var polls = 0
        while endpoint == nil, polls < Self.discoveryPolls {
            try? await Task.sleep(for: .milliseconds(250))
            endpoint = discovered[hubID]?.endpoint
            polls += 1
        }
        guard let endpoint else { return .failure(.hubNotFound) }
        guard let parameters = LinkTLS.parameters(credentials: [keys.credential]) else {
            return .failure(.connectionFailed)
        }
        let link = Link(connection: NWConnection(to: endpoint, using: parameters), outbound: Outbound(hubID: hubID))
        link.keys = keys
        return await withCheckedContinuation { continuation in
            link.waiter = continuation
            start(link)
        }
    }

    private func startBrowser() {
        guard localDevice.role == .companion, browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: HomePadIdentifiers.bonjourServiceType, domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let hubs = results.compactMap { result -> DiscoveredHub? in
                guard case .service(let name, _, _, _) = result.endpoint,
                      case .bonjour(let record) = result.metadata,
                      let advertisement = HubAdvertisement.parse(serviceName: name, txtRecord: record.dictionary)
                else { return nil }
                return DiscoveredHub(advertisement: advertisement, endpoint: result.endpoint)
            }
            self?.assumeIsolated { $0.browseResultsChanged(hubs) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            self?.assumeIsolated { $0.browserStateChanged(state) }
        }
        browser.start(queue: queue)
        self.browser = browser
        snapshot.isBrowsing = true
        publish()
    }

    private func browserStateChanged(_ state: NWBrowser.State) {
        switch state {
        case .waiting(let error), .failed(let error):
            snapshot.isLocalNetworkDenied = Self.isPolicyDenied(error)
        case .ready:
            snapshot.isLocalNetworkDenied = false
        default:
            break
        }
        publish()
    }

    private func browseResultsChanged(_ hubs: [DiscoveredHub]) {
        discovered = Dictionary(hubs.map { ($0.advertisement.hubID, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.visibleHubs = hubs.map(\.advertisement).sorted { $0.name < $1.name }
        publish()
        let pairedHubs = (try? store.devices().map(\.id)) ?? []
        for hubID in pairedHubs where discovered[hubID] != nil && connecting[hubID] == nil {
            guard !links.values.contains(where: { $0.outbound?.hubID == hubID }) else { continue }
            Task { _ = try? await self.connect(to: hubID, userInitiated: false) }
        }
    }

    private func verifyHub(_ hello: LinkHello, on link: Link, outbound: Outbound) {
        guard let keys = link.keys,
              case .success(let hub) = CompanionAuthenticator.verify(hubHello: hello, expectedHubID: outbound.hubID, keys: keys)
        else {
            log.notice("The hub's hello did not match the pairing")
            close(link, sending: .unauthorized, error: .handshakeRejected)
            return
        }
        established(link, peer: hub)
    }

    // MARK: Connections

    private func start(_ link: Link) {
        links[link.id] = link
        let linkID = link.id
        link.connection.stateUpdateHandler = { [weak self] state in
            self?.assumeIsolated { $0.connectionStateChanged(linkID, state) }
        }
        link.connection.start(queue: queue)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(LinkLimits.handshakeTimeout))
            await self?.expireHandshake(linkID)
        }
    }

    private func expireHandshake(_ linkID: UUID) {
        guard let link = links[linkID], link.peer == nil else { return }
        close(link, sending: nil, error: .connectionFailed)
    }

    private func connectionStateChanged(_ linkID: UUID, _ state: NWConnection.State) {
        guard let link = links[linkID] else { return }
        switch state {
        case .ready:
            // Reached only after the TLS handshake has authenticated both ends.
            if link.outbound != nil {
                guard let keys = link.keys,
                      let hello = try? LinkSession.frame(.hello(CompanionAuthenticator.hello(companion: localDevice, keys: keys)))
                else {
                    close(link, sending: nil, error: .invalidMessage)
                    return
                }
                link.connection.send(content: hello, completion: .contentProcessed { _ in })
            }
            receiveNext(linkID)
        case .waiting(let error), .failed(let error):
            if case .tls = error {
                close(link, sending: nil, error: .handshakeRejected)
            } else {
                close(link, sending: nil, error: .connectionFailed)
            }
        case .cancelled:
            close(link, sending: nil, error: .connectionFailed)
        default:
            break
        }
    }

    private func receiveNext(_ linkID: UUID) {
        guard let link = links[linkID] else { return }
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: LinkLimits.receiveChunkSize) { [weak self] data, _, isComplete, error in
            self?.assumeIsolated { $0.received(linkID, data: data, isFinished: isComplete || error != nil) }
        }
    }

    private func received(_ linkID: UUID, data: Data?, isFinished: Bool) {
        guard let link = links[linkID] else { return }
        if let data, !data.isEmpty {
            handle(link.session.receive(data), on: link)
        }
        guard links[linkID] != nil else { return }
        if isFinished {
            close(link, sending: nil, error: .connectionFailed)
        } else {
            receiveNext(linkID)
        }
    }

    private func handle(_ events: [LinkSessionEvent], on link: Link) {
        for event in events {
            guard links[link.id] != nil else { return }
            switch event {
            case .hello(let hello):
                if let outbound = link.outbound {
                    verifyHub(hello, on: link, outbound: outbound)
                } else {
                    admit(hello, on: link)
                }
            case .envelope(let envelope):
                fanout.publish(envelope)
            case .reply(let frame):
                link.connection.send(content: frame, completion: .contentProcessed { _ in })
            case .pong:
                break
            case .close(let reason):
                let error: PeerLinkError = reason == .unauthorized || reason == .revoked ? .handshakeRejected : .connectionFailed
                close(link, sending: nil, error: error)
            }
        }
    }

    private func established(_ link: Link, peer: PeerDevice) {
        link.peer = peer
        link.waiter?.resume(returning: .success(peer))
        link.waiter = nil
        publish()
        eventContinuation.yield(.peerConnected(peer))
        handle(link.session.establish(peerID: peer.id), on: link)
    }

    private func close(_ link: Link, sending reason: LinkCloseReason?, error: PeerLinkError) {
        guard links.removeValue(forKey: link.id) != nil else { return }
        link.session.close()
        link.connection.stateUpdateHandler = nil
        let connection = link.connection
        if let reason, let frame = try? LinkSession.frame(.bye(reason)) {
            connection.send(content: frame, completion: .contentProcessed { _ in connection.cancel() })
        } else {
            connection.cancel()
        }
        link.waiter?.resume(returning: .failure(error))
        link.waiter = nil
        guard let peer = link.peer else { return }
        publish()
        eventContinuation.yield(.peerDisconnected(peer.id))
        if let outbound = link.outbound, browser != nil, error == .connectionFailed, discovered[outbound.hubID] != nil {
            Task { _ = try? await self.connect(to: outbound.hubID, userInitiated: false) }
        }
    }

    private func write(_ frame: Data, to connection: NWConnection) async throws(PeerLinkError) {
        let delivered = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
        guard delivered else { throw .connectionFailed }
    }

    private func establishedPeers() -> [PeerDevice] {
        links.values.compactMap(\.peer).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func publish() {
        snapshot.connectedPeers = establishedPeers()
        statusContinuation.yield(snapshot)
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == policyDeniedCode }
        return false
    }

    /// The DNS-SD code for "local network access denied by the user".
    private static let policyDeniedCode: Int32 = -65570
    private static let backgroundAttemptLimit = 5
    private static let discoveryPolls = 24
}

private struct HubConfiguration {
    var sceneActive = false
    var receiveEnabled = false
    var hubName = BeamSettings.hubName.defaultValue
}

private struct Outbound {
    let hubID: UUID
}

private struct DiscoveredHub {
    let advertisement: HubAdvertisement
    let endpoint: NWEndpoint
}

/// One connection. Only touched on the link's queue.
private final class Link {
    let id = UUID()
    let connection: NWConnection
    let outbound: Outbound?
    var session = LinkSession()
    var peer: PeerDevice?
    /// The pairing keys this connection was authenticated with.
    var keys: LinkKeys?
    var waiter: CheckedContinuation<Result<PeerDevice, PeerLinkError>, Never>?

    init(connection: NWConnection, outbound: Outbound?) {
        self.connection = connection
        self.outbound = outbound
    }
}
