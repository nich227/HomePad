import Foundation
import HomePadCore

/// The biometric sensor the device can use right now. `none` also covers a sensor that is not
/// set up or is locked out, because it cannot be used either way.
public enum DeviceBiometryKind: String, Equatable, Sendable {
    case none
    case touchID
    case faceID
}

/// What one biometric prompt reported.
public enum BiometricAttemptResult: Equatable, Sendable {
    case success
    /// The finger was not recognized.
    case failed
    /// The person or the system dismissed the prompt.
    case canceled
    /// Too many failed attempts. Biometrics stay off until the device passcode is entered.
    case lockedOut
    case notAvailable

    /// Maps a LocalAuthentication error code to a result. The codes are the `LAError` values:
    /// -1 authentication failed, -2 user cancel, -3 user fallback, -4 system cancel, -8 biometry
    /// lockout, -9 app cancel. The fallback button is hidden, so -3 is not expected and counts as
    /// a cancel. Every other code means biometrics cannot be used.
    public init(localAuthenticationErrorCode code: Int) {
        switch code {
        case -1: self = .failed
        case -2, -3, -4, -9: self = .canceled
        case -8: self = .lockedOut
        default: self = .notAvailable
        }
    }
}

/// How an unlock attempt ended, and what the app does about it.
public enum DeviceBiometricUnlockOutcome: Equatable, Sendable {
    /// Personal content of the camera-matched member is unlocked until they leave.
    case confirmed
    /// Nothing changes. Say that the finger was not recognized and let the person try again.
    case failed
    /// Nothing changes and nothing is said. The person may try again.
    case canceled
    /// Nothing changes. Say that Touch ID is locked until the iPad is unlocked with its passcode,
    /// and stop offering it until then.
    case lockedOut
    /// Nothing changes and no prompt result is used: the unlock is not offered, another attempt
    /// is in progress, or the camera match was gone when the prompt returned.
    case notAvailable

    public var unlocksPersonalContent: Bool { self == .confirmed }
    public var showsFailure: Bool { self == .failed || self == .lockedOut }
    public var mayRetry: Bool { self == .failed || self == .canceled }
}

/// The system's biometric prompt. The app implements it with LocalAuthentication, tests with a
/// fake.
public protocol DeviceBiometricAuthenticating: Sendable {
    func biometryKind() -> DeviceBiometryKind
    /// Shows the prompt. Each call must start from scratch, so an earlier success is never reused.
    func authenticate(reason: String) async -> BiometricAttemptResult
}

public enum DeviceBiometricUnlockPolicy {
    /// Touch ID is offered only as the second step after the camera picked a member, and only
    /// where the camera cannot prove liveness on its own.
    ///
    /// - Parameters:
    ///   - settingEnabled: the "Unlock with Touch ID" preference.
    ///   - hasDepthCamera: with a depth camera the liveness check decides, and Touch ID stays out
    ///     of it.
    ///   - cameraMatchWaiting: the camera matched a member without proven liveness and that match
    ///     is still the active profile. False for a profile someone picked by hand, because a
    ///     fingerprint says nothing about which member is present.
    public static func isOffered(
        settingEnabled: Bool,
        biometry: DeviceBiometryKind,
        hasDepthCamera: Bool,
        cameraMatchWaiting: Bool
    ) -> Bool {
        settingEnabled && biometry == .touchID && !hasDepthCamera && cameraMatchWaiting
    }

    /// - Parameter cameraMatchStillWaiting: whether the same camera match is still waiting now
    ///   that the prompt has returned. The person may have left while it was showing.
    public static func outcome(of result: BiometricAttemptResult, cameraMatchStillWaiting: Bool) -> DeviceBiometricUnlockOutcome {
        switch result {
        case .success: cameraMatchStillWaiting ? .confirmed : .notAvailable
        case .failed: .failed
        case .canceled: .canceled
        case .lockedOut: .lockedOut
        case .notAvailable: .notAvailable
        }
    }
}

/// Runs one unlock attempt against the household session: checks that it is offered, prompts,
/// checks again, and only then confirms.
@MainActor
public final class DeviceBiometricUnlockFlow {
    public private(set) var isAuthenticating = false
    private let session: HouseholdSession
    private let authenticator: any DeviceBiometricAuthenticating

    public init(session: HouseholdSession, authenticator: any DeviceBiometricAuthenticating) {
        self.session = session
        self.authenticator = authenticator
    }

    public func isOffered(settingEnabled: Bool, biometry: DeviceBiometryKind, hasDepthCamera: Bool) -> Bool {
        DeviceBiometricUnlockPolicy.isOffered(
            settingEnabled: settingEnabled,
            biometry: biometry,
            hasDepthCamera: hasDepthCamera,
            cameraMatchWaiting: session.canConfirmWithDeviceBiometrics
        )
    }

    public func unlock(
        settingEnabled: Bool,
        biometry: DeviceBiometryKind,
        hasDepthCamera: Bool,
        reason: String,
        at date: Date
    ) async -> DeviceBiometricUnlockOutcome {
        guard
            !isAuthenticating,
            isOffered(settingEnabled: settingEnabled, biometry: biometry, hasDepthCamera: hasDepthCamera),
            let matched = session.cameraMatchedProfileID
        else { return .notAvailable }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await authenticator.authenticate(reason: reason)
        // The prompt can stay up for a while. The fingerprint only counts for the member the
        // camera had matched when it was requested, and only if they are still there.
        let stillWaiting = session.canConfirmWithDeviceBiometrics && session.cameraMatchedProfileID == matched
        let outcome = DeviceBiometricUnlockPolicy.outcome(of: result, cameraMatchStillWaiting: stillWaiting)
        if outcome == .confirmed {
            session.confirmWithDeviceBiometrics(at: date)
        }
        return outcome
    }
}
