import Foundation
import FoundationModels
import HomePadAssistantCore
import Observation

extension AssistantTestHooks {
    /// The switches for this launch. Read once, and only in debug builds.
    public static let current: AssistantTestHooks = {
        #if DEBUG
        return AssistantTestHooks(environment: ProcessInfo.processInfo.environment)
        #else
        return .none
        #endif
    }()
}

extension SystemModelStatus {
    init(_ availability: SystemLanguageModel.Availability) {
        self = switch availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady): .unavailable(.modelNotReady)
        case .unavailable: .unavailable(.other)
        }
    }

    /// What the system says about the on-device model right now. This is the one public sign
    /// that Apple Intelligence is on: the system has no call that reports Siri's own state.
    public static var current: SystemModelStatus {
        SystemModelStatus(SystemLanguageModel.default.availability)
    }
}

/// Holds the answer to "may HomePad run". The app shows `AppleIntelligenceRequiredView` instead
/// of its own scene whenever `mayRun` is false.
@MainActor
@Observable
public final class AppleIntelligenceGate {
    public private(set) var decision: AssistantGateDecision
    public private(set) var availability: AssistantAvailability

    @ObservationIgnored private var state: AssistantGateState
    @ObservationIgnored private let read: @MainActor () -> SystemModelStatus
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var recheck: Task<Void, Never>?

    /// Reads availability once. Call `refresh` whenever the scene becomes active.
    public init(
        hooks: AssistantTestHooks = .current,
        read: @escaping @MainActor () -> SystemModelStatus = { .current },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.read = read
        self.now = now
        let date = now()
        let state = AssistantGateState(AssistantAvailability(read()), at: date, isBypassed: hooks.skipsAppleIntelligenceGate)
        self.state = state
        decision = state.decision(at: date)
        availability = state.availability
        scheduleRecheck()
        observeSystemModel()
    }

    public var mayRun: Bool {
        decision.mayRun
    }

    /// Reads availability again. While the model is preparing the gate also reads by itself
    /// every few seconds, so the waiting screen gives way without a touch.
    public func refresh() {
        let date = now()
        state.update(AssistantAvailability(read()), at: date)
        decision = state.decision(at: date)
        availability = state.availability
        scheduleRecheck()
    }

    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = nil
        guard state.shouldRecheck else { return }
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AssistantGateState.recheckInterval))
            if !Task.isCancelled {
                self?.refresh()
            }
        }
    }

    /// The system model announces its own changes, so a change made in Settings while HomePad
    /// shares the screen with it is picked up without waiting for the scene to become active.
    private func observeSystemModel() {
        withObservationTracking {
            _ = SystemLanguageModel.default.availability
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeSystemModel()
            }
        }
    }
}
