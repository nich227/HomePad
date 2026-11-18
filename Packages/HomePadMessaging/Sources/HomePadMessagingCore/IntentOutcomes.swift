import Foundation

/// The result of relaying one incoming message, reported back to the Shortcuts automation.
public enum MessageRelayOutcome: Sendable, Equatable {
    /// Sent to this many hubs.
    case delivered(hubCount: Int)
    /// No hub was reachable in time. The message waits on the iPhone and shows when one connects.
    case keptForLater
    /// The same message was relayed a moment ago.
    case duplicate
    /// Messages projection is turned off in Settings.
    case disabled
    case rejected(RelayedMessageError)
    /// The app has not registered its handlers, which means it has not finished launching.
    case unavailable

    public var wasDelivered: Bool {
        if case .delivered = self { return true }
        return false
    }
}

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
