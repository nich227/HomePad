import Foundation

/// The result of a command an intent sent to a hub.
public enum HubCommandOutcome: Sendable, Equatable {
    case delivered(hubCount: Int)
    case noHubReachable
    /// The request was refused before sending: a bad URL, an unknown app, a feature turned off.
    case rejected
    case unavailable

    public var wasDelivered: Bool {
        if case .delivered = self { return true }
        return false
    }
}

/// How long an intent waits for a hub link before giving up. Shortcuts stops an action that runs
/// much longer than this.
public enum IntentTiming {
    public static let hubWait: TimeInterval = 8
    public static let pollInterval: TimeInterval = 0.25

    /// Whether to keep waiting for a hub, given when the wait started.
    public static func shouldKeepWaiting(startedAt: Date, now: Date, limit: TimeInterval = hubWait) -> Bool {
        now.timeIntervalSince(startedAt) < limit
    }
}
