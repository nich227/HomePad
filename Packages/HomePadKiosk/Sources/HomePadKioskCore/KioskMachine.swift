import Foundation
import HomePadCore

public enum KioskSettings {
    public static let pane = "Kiosk Lock"

    public static let enabled = SettingKey<Bool>("kiosk.enabled", default: false)
    public static let relockSeconds = SettingKey<Int>("kiosk.relockSeconds", default: 30)

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(
            enabled,
            title: "Require Passcode to Leave HomePad",
            pane: pane,
            footer: "HomePad locks this iPad to itself. To get to the Home Screen, tap the lock in HomePad and enter the iPad passcode. iPadOS allows an app to do this only on a supervised iPad that permits HomePad to use Single App Mode. On any other iPad, use Guided Access: turn it on in Settings > Accessibility, then triple-click the top button while HomePad is open."
        ),
        SettingDescriptor(
            relockSeconds,
            title: "Lock Again After",
            pane: pane,
            options: [
                .init(title: "15 Seconds", value: "15"),
                .init(title: "30 Seconds", value: "30"),
                .init(title: "1 Minute", value: "60"),
                .init(title: "5 Minutes", value: "300"),
            ],
            footer: "After the passcode is entered, HomePad stays unlocked for this long if nobody leaves it."
        ),
    ]
}

public enum KioskLockMethod: Equatable, Sendable {
    /// The app locked itself with Single App Mode. It can release the lock after a passcode check.
    case singleAppMode
    /// Someone started Guided Access by hand. Only the system can end it.
    case guidedAccess
}

public enum KioskUnavailableReason: Equatable, Sendable {
    /// Locking with no passcode set would leave no way to verify who unlocks.
    case noPasscode
    /// The iPad is not supervised, or does not allow this app to lock itself.
    case notPermitted
}

public enum KioskState: Equatable, Sendable {
    case off
    case engaging
    case locked(KioskLockMethod)
    case authenticating
    case releasing
    case released(relockAt: Date)
    case unavailable(KioskUnavailableReason)
}

public enum PasscodeOutcome: Equatable, Sendable {
    case accepted
    case rejected
    case notSet
}

public enum KioskEvent: Equatable, Sendable {
    case configuration(enabled: Bool, passcodeSet: Bool, relockSeconds: Int)
    case sceneActivated
    case sceneBackgrounded
    case engageFinished(success: Bool)
    case guidedAccessChanged(active: Bool)
    case unlockTapped
    case passcode(PasscodeOutcome)
    case releaseFinished(success: Bool)
    case relockTimerFired
}

public enum KioskEffect: Equatable, Sendable {
    case setSingleAppMode(Bool)
    case promptForPasscode
    case scheduleRelock(at: Date)
    case cancelRelock
}

/// Decides when the app locks the iPad to itself and when it lets go. Holds no system references;
/// the controller feeds it events and performs the effects it returns.
public struct KioskMachine: Equatable, Sendable {
    public private(set) var state: KioskState = .off
    private var enabled = false
    private var passcodeSet = false
    private var relockInterval: TimeInterval = 30
    private var guidedAccessActive = false
    private var ownsSession = false
    private var leftAppWhileReleased = false

    public init() {}

    public mutating func handle(_ event: KioskEvent, now: Date) -> [KioskEffect] {
        switch event {
        case .configuration(let enabled, let passcodeSet, let relockSeconds):
            self.enabled = enabled
            self.passcodeSet = passcodeSet
            relockInterval = TimeInterval(max(relockSeconds, 5))
            return enabled ? reconcile(retryingPermission: false) : turnOff()

        case .sceneActivated:
            return enabled ? reconcile(retryingPermission: true) : []

        case .sceneBackgrounded:
            guard case .released = state else { return [] }
            leftAppWhileReleased = true
            return [.cancelRelock]

        case .engageFinished(let success):
            guard state == .engaging else {
                // The setting was switched off while the request was in flight.
                return success ? [.setSingleAppMode(false)] : []
            }
            ownsSession = success
            state = success ? .locked(.singleAppMode) : .unavailable(.notPermitted)
            return []

        case .guidedAccessChanged(let active):
            guidedAccessActive = active
            return guidedAccessChanged(active: active)

        case .unlockTapped:
            guard state == .locked(.singleAppMode) else { return [] }
            state = .authenticating
            return [.promptForPasscode]

        case .passcode(let outcome):
            guard state == .authenticating else { return [] }
            switch outcome {
            case .accepted, .notSet:
                state = .releasing
                return [.setSingleAppMode(false)]
            case .rejected:
                state = .locked(.singleAppMode)
                return []
            }

        case .releaseFinished(let success):
            guard state == .releasing else { return [] }
            guard success else {
                state = .locked(.singleAppMode)
                return []
            }
            ownsSession = false
            leftAppWhileReleased = false
            let deadline = now.addingTimeInterval(relockInterval)
            state = .released(relockAt: deadline)
            return [.scheduleRelock(at: deadline)]

        case .relockTimerFired:
            guard case .released(let deadline) = state, now >= deadline, enabled else { return [] }
            return engage()
        }
    }

    private mutating func turnOff() -> [KioskEffect] {
        let wasOwned = ownsSession
        ownsSession = false
        leftAppWhileReleased = false
        state = .off
        return wasOwned ? [.setSingleAppMode(false), .cancelRelock] : [.cancelRelock]
    }

    /// Brings the state in line with the setting. Leaves in-flight and already-locked states alone.
    /// A refused lock request is retried only when the scene activates, because the permission can
    /// change only while the app is not frontmost.
    private mutating func reconcile(retryingPermission: Bool) -> [KioskEffect] {
        switch state {
        case .engaging, .locked, .authenticating, .releasing:
            return []
        case .released:
            return leftAppWhileReleased ? engage() : []
        case .unavailable(.notPermitted):
            return retryingPermission ? engage() : []
        case .off, .unavailable(.noPasscode):
            return engage()
        }
    }

    private mutating func engage() -> [KioskEffect] {
        leftAppWhileReleased = false
        if guidedAccessActive, !ownsSession {
            state = .locked(.guidedAccess)
            return [.cancelRelock]
        }
        guard passcodeSet else {
            state = .unavailable(.noPasscode)
            return [.cancelRelock]
        }
        state = .engaging
        return [.cancelRelock, .setSingleAppMode(true)]
    }

    private mutating func guidedAccessChanged(active: Bool) -> [KioskEffect] {
        guard enabled else { return [] }
        if active {
            switch state {
            case .off, .unavailable, .released:
                // Started by hand while the app could not, or had not yet, locked itself.
                state = .locked(.guidedAccess)
                return [.cancelRelock]
            case .engaging, .locked, .authenticating, .releasing:
                return []
            }
        }
        switch state {
        case .locked(.guidedAccess):
            return engage()
        case .locked(.singleAppMode), .authenticating:
            // The session ended from outside the app, for example by device management.
            ownsSession = false
            return engage()
        case .off, .engaging, .releasing, .released, .unavailable:
            return []
        }
    }
}
