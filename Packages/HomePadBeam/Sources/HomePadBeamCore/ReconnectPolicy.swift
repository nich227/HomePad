import Foundation

/// When and how long to wait before trying a connection again.
public struct ReconnectPolicy: Equatable, Sendable {
    public var baseDelay: TimeInterval
    public var maximumDelay: TimeInterval
    /// The delay varies by up to this fraction either way, so devices that lost the hub together
    /// do not all come back at the same instant.
    public var jitterFraction: Double
    /// A send the person asked for stops after this many tries and reports the failure.
    public var userInitiatedAttempts: Int

    public init(baseDelay: TimeInterval = 0.5, maximumDelay: TimeInterval = 8, jitterFraction: Double = 0.25, userInitiatedAttempts: Int = 3) {
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.jitterFraction = jitterFraction
        self.userInitiatedAttempts = userInitiatedAttempts
    }

    /// - Parameters:
    ///   - attempt: The number of tries already made, starting at 1.
    ///   - jitter: A random value in 0..<1.
    public func delay(afterAttempt attempt: Int, jitter: Double) -> TimeInterval {
        let exponent = Double(min(max(attempt, 1), 30) - 1)
        let nominal = min(baseDelay * pow(2, exponent), maximumDelay)
        let spread = (min(max(jitter, 0), 1) * 2 - 1) * jitterFraction
        return nominal * (1 + spread)
    }

    public func shouldRetry(afterAttempt attempt: Int, userInitiated: Bool) -> Bool {
        !userInitiated || attempt < userInitiatedAttempts
    }
}
