import Foundation

/// Allows at most `limit` events per key in any `window`. The caller supplies the time.
public struct RateLimiter<Key: Hashable & Sendable>: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var events: [Key: [Date]] = [:]

    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    public mutating func allow(_ key: Key, now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-window)
        for (other, dates) in events {
            let recent = dates.filter { $0 > cutoff }
            events[other] = recent.isEmpty ? nil : recent
        }
        let recent = events[key] ?? []
        guard recent.count < limit else { return false }
        events[key] = recent + [now]
        return true
    }

    public mutating func reset(_ key: Key) {
        events[key] = nil
    }
}
