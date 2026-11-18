import Foundation
import HomePadCore

/// Delivers received envelopes to everyone subscribed to their channel.
public final class EnvelopeFanout: @unchecked Sendable {
    /// A subscriber that stops reading keeps only this many envelopes; older ones are dropped.
    public static let bufferLimit = 128

    private let lock = NSLock()
    private var subscribers: [String: [UUID: AsyncStream<PeerEnvelope>.Continuation]] = [:]

    public init() {}

    public func subscribe(to channel: String) -> AsyncStream<PeerEnvelope> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(Self.bufferLimit)) { continuation in
            lock.withLock { subscribers[channel, default: [:]][token] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.remove(token, from: channel)
            }
        }
    }

    public func publish(_ envelope: PeerEnvelope) {
        let targets = lock.withLock { subscribers[envelope.channel].map { Array($0.values) } ?? [] }
        for continuation in targets {
            continuation.yield(envelope)
        }
    }

    public func subscriberCount(for channel: String) -> Int {
        lock.withLock { subscribers[channel]?.count ?? 0 }
    }

    /// Ends every stream. Used when the link is torn down for good.
    public func finishAll() {
        let all = lock.withLock { () -> [AsyncStream<PeerEnvelope>.Continuation] in
            defer { subscribers = [:] }
            return subscribers.values.flatMap(\.values)
        }
        for continuation in all {
            continuation.finish()
        }
    }

    private func remove(_ token: UUID, from channel: String) {
        lock.withLock {
            subscribers[channel]?[token] = nil
            if subscribers[channel]?.isEmpty == true {
                subscribers[channel] = nil
            }
        }
    }
}
