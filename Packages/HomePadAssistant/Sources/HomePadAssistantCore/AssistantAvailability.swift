import Foundation

/// What the system reports for the on-device language model, restated without the framework's
/// types so the mapping can be tested.
public enum SystemModelStatus: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        /// A reason this build does not know.
        case other
    }

    case available
    case unavailable(Reason)
}

/// Whether the Assistant, and with it the app, can work on this device right now.
public enum AssistantAvailability: Equatable, Sendable {
    case available
    /// Apple Intelligence is off in Settings.
    case needsAppleIntelligence
    case deviceNotEligible
    /// Apple Intelligence is on and the model is still downloading or loading.
    case preparing
    case unknown

    public init(_ status: SystemModelStatus) {
        self = switch status {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .needsAppleIntelligence
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.modelNotReady): .preparing
        case .unavailable(.other): .unknown
        }
    }
}

public enum AssistantGateDecision: Equatable, Sendable {
    public enum Block: Equatable, Sendable {
        case needsAppleIntelligence
        case deviceNotEligible
        /// The model has been preparing for longer than the grace period.
        case stillPreparing
        case unknown
    }

    /// Show the app.
    case run
    /// Show a waiting screen. Nothing is asked of the person.
    case gettingReady
    /// Show the screen that says what to change.
    case blocked(Block)

    public var mayRun: Bool { self == .run }
}

/// Decides whether the app may run. The app runs only while the model is available, with one
/// exception: a model that is preparing gets a grace period. During it a hub that was already
/// running keeps running, and a hub that has not started yet shows a waiting screen.
public struct AssistantGateState: Equatable, Sendable {
    public static let preparingGracePeriod: TimeInterval = 600
    /// How often to read availability again while the model is preparing.
    public static let recheckInterval: TimeInterval = 5

    public let isBypassed: Bool
    public private(set) var availability: AssistantAvailability
    /// When `availability` last changed.
    public private(set) var since: Date
    /// Whether the model has been available since the last time the app was blocked.
    public private(set) var hubHasRun: Bool

    public init(_ availability: AssistantAvailability, at now: Date, isBypassed: Bool = false) {
        self.isBypassed = isBypassed
        self.availability = availability
        since = now
        hubHasRun = availability == .available
    }

    public mutating func update(_ availability: AssistantAvailability, at now: Date) {
        if availability != self.availability {
            since = now
        }
        self.availability = availability
        switch availability {
        case .available: hubHasRun = true
        case .preparing: break
        case .needsAppleIntelligence, .deviceNotEligible, .unknown: hubHasRun = false
        }
    }

    public func decision(at now: Date) -> AssistantGateDecision {
        if isBypassed { return .run }
        switch availability {
        case .available:
            return .run
        case .needsAppleIntelligence:
            return .blocked(.needsAppleIntelligence)
        case .deviceNotEligible:
            return .blocked(.deviceNotEligible)
        case .unknown:
            return .blocked(.unknown)
        case .preparing:
            guard now.timeIntervalSince(since) < Self.preparingGracePeriod else {
                return .blocked(.stillPreparing)
            }
            return hubHasRun ? .run : .gettingReady
        }
    }

    /// Whether the answer can change without anyone touching Settings.
    public var shouldRecheck: Bool {
        !isBypassed && availability == .preparing
    }
}

/// Switches set only by the UI tests, through the launch environment. Every one is off unless
/// its variable is present, and release builds never read them.
public struct AssistantTestHooks: Equatable, Sendable {
    /// Run the app whatever the model's availability is. A simulator may have no model.
    public let skipsAppleIntelligenceGate: Bool
    /// Answer from a fixed script instead of the model.
    public let usesScriptedAssistant: Bool

    public static let none = AssistantTestHooks(environment: [:])

    public init(environment: [String: String]) {
        skipsAppleIntelligenceGate = environment["HOMEPAD_UITEST_SKIP_AI_GATE"] == "1"
        usesScriptedAssistant = environment["HOMEPAD_UITEST_SCRIPTED_ASSISTANT"] == "1"
    }
}
