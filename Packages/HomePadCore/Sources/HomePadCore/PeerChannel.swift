import Foundation

/// A paired device on the other end of an authenticated link.
public struct PeerDevice: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var role: DeviceRole
    /// The household member this device belongs to, when it is a companion.
    public var profileID: UUID?

    public init(id: UUID, name: String, role: DeviceRole, profileID: UUID? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.profileID = profileID
    }
}

public struct PeerEnvelope: Codable, Equatable, Sendable {
    public let channel: String
    public let sender: UUID
    public let payload: Data

    public init(channel: String, sender: UUID, payload: Data) {
        self.channel = channel
        self.sender = sender
        self.payload = payload
    }
}

public enum PeerChannelName {
    public static let beam = "beam"
    public static let projection = "projection"
    public static let presence = "presence"
    public static let intercom = "intercom"
}

public enum PeerChannelError: Error, Equatable, Sendable {
    case notConnected
    case unknownPeer(UUID)
}

/// Message transport between a hub and its paired companions. Implementations deliver only to and
/// from peers that have already been authenticated; callers never see traffic from unpaired devices.
public protocol PeerChannel: Sendable {
    var localDevice: PeerDevice { get }
    func connectedPeers() async -> [PeerDevice]
    /// `peer == nil` sends to every connected peer.
    func send(_ payload: Data, on channel: String, to peer: UUID?) async throws
    func messages(on channel: String) -> AsyncStream<PeerEnvelope>
}

extension PeerChannel {
    public func send<Message: Encodable>(_ message: Message, on channel: String, to peer: UUID? = nil) async throws {
        try await send(JSONEncoder().encode(message), on: channel, to: peer)
    }

    public func decoded<Message: Decodable & Sendable>(_ type: Message.Type, on channel: String) -> AsyncStream<(sender: UUID, message: Message)> {
        let source = messages(on: channel)
        return AsyncStream { continuation in
            let task = Task {
                let decoder = JSONDecoder()
                for await envelope in source {
                    if let message = try? decoder.decode(Message.self, from: envelope.payload) {
                        continuation.yield((envelope.sender, message))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Two in-process endpoints wired to each other. For tests and SwiftUI previews.
public final class LoopbackPeerChannel: PeerChannel, @unchecked Sendable {
    public let localDevice: PeerDevice
    private let lock = NSLock()
    private var remote: LoopbackPeerChannel?
    private var subscribers: [String: [UUID: AsyncStream<PeerEnvelope>.Continuation]] = [:]

    private init(localDevice: PeerDevice) {
        self.localDevice = localDevice
    }

    public static func pair(_ first: PeerDevice, _ second: PeerDevice) -> (LoopbackPeerChannel, LoopbackPeerChannel) {
        let a = LoopbackPeerChannel(localDevice: first)
        let b = LoopbackPeerChannel(localDevice: second)
        a.remote = b
        b.remote = a
        return (a, b)
    }

    public func disconnect() {
        let other = lock.withLock { () -> LoopbackPeerChannel? in
            defer { remote = nil }
            return remote
        }
        other?.lock.withLock { other?.remote = nil }
    }

    public func connectedPeers() async -> [PeerDevice] {
        lock.withLock { remote.map { [$0.localDevice] } ?? [] }
    }

    public func send(_ payload: Data, on channel: String, to peer: UUID?) async throws {
        guard let remote = lock.withLock({ remote }) else { throw PeerChannelError.notConnected }
        if let peer, peer != remote.localDevice.id { throw PeerChannelError.unknownPeer(peer) }
        remote.deliver(PeerEnvelope(channel: channel, sender: localDevice.id, payload: payload))
    }

    public func messages(on channel: String) -> AsyncStream<PeerEnvelope> {
        let token = UUID()
        return AsyncStream { continuation in
            lock.withLock { subscribers[channel, default: [:]][token] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.subscribers[channel]?.removeValue(forKey: token) }
            }
        }
    }

    private func deliver(_ envelope: PeerEnvelope) {
        let targets = lock.withLock { subscribers[envelope.channel].map { Array($0.values) } ?? [] }
        for continuation in targets {
            continuation.yield(envelope)
        }
    }
}
