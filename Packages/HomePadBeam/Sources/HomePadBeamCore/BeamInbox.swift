import Foundation

/// Beams waiting for someone at the hub to decide, and the pages opened recently.
public struct BeamInbox: Equatable, Sendable {
    public enum EnqueueResult: Equatable, Sendable {
        case queued
        /// The same page from the same device is already waiting.
        case duplicate
    }

    public let pendingLimit: Int
    public let historyLimit: Int
    public let pendingLifetime: TimeInterval

    private struct Entry: Equatable, Sendable {
        let beam: BeamPayload
        let enqueuedAt: Date
    }

    private var entries: [Entry] = []
    /// Newest first.
    public private(set) var history: [BeamPayload] = []

    /// Oldest first.
    public var pending: [BeamPayload] { entries.map(\.beam) }

    public init(pendingLimit: Int = 8, historyLimit: Int = 50, pendingLifetime: TimeInterval = 600) {
        self.pendingLimit = pendingLimit
        self.historyLimit = historyLimit
        self.pendingLifetime = pendingLifetime
    }

    public mutating func enqueue(_ beam: BeamPayload, now: Date) -> EnqueueResult {
        pruneExpired(now: now)
        if entries.contains(where: { $0.beam.id == beam.id || ($0.beam.url == beam.url && $0.beam.sender.id == beam.sender.id) }) {
            return .duplicate
        }
        entries.append(Entry(beam: beam, enqueuedAt: now))
        if entries.count > pendingLimit {
            entries.removeFirst(entries.count - pendingLimit)
        }
        return .queued
    }

    /// Takes a beam out of the waiting list, whether it was approved or declined.
    public mutating func resolve(id: UUID) -> BeamPayload? {
        guard let index = entries.firstIndex(where: { $0.beam.id == id }) else { return nil }
        return entries.remove(at: index).beam
    }

    public mutating func recordOpened(_ beam: BeamPayload) {
        history.removeAll { $0.url == beam.url }
        history.insert(beam, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
    }

    public mutating func clearHistory() {
        history = []
    }

    @discardableResult
    public mutating func pruneExpired(now: Date) -> [BeamPayload] {
        let cutoff = now.addingTimeInterval(-pendingLifetime)
        let expired = entries.filter { $0.enqueuedAt <= cutoff }.map(\.beam)
        entries.removeAll { $0.enqueuedAt <= cutoff }
        return expired
    }

    /// Drops everything a device sent, for when it is revoked.
    public mutating func removeAll(from deviceID: UUID) {
        entries.removeAll { $0.beam.sender.id == deviceID }
        history.removeAll { $0.sender.id == deviceID }
    }
}
