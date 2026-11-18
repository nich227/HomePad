import Foundation
import HomePadCore
import HomePadFaceCore
import LocalAuthentication
import Observation
import SwiftUI
import UIKit

/// The system's biometric prompt, through LocalAuthentication.
public struct LocalAuthenticationAuthenticator: DeviceBiometricAuthenticating {
    public init() {}

    public func biometryKind() -> DeviceBiometryKind {
        let context = LAContext()
        // The sensor type is only reported after this check, and a sensor that is not set up or
        // is locked out counts as none.
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .touchID: return .touchID
        case .faceID: return .faceID
        default: return .none
        }
    }

    public func authenticate(reason: String) async -> BiometricAttemptResult {
        // A new context for every attempt, so an earlier success is never reused.
        let context = LAContext()
        // Biometrics only. Hiding the fallback button keeps the iPad passcode out of this: knowing
        // the passcode must not unlock a household member's content.
        context.localizedFallbackTitle = ""
        do {
            let accepted = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return accepted ? .success : .failed
        } catch let error as LAError {
            return BiometricAttemptResult(localAuthenticationErrorCode: error.errorCode)
        } catch {
            return .notAvailable
        }
    }
}

/// Touch ID as the second step on an iPad whose camera cannot prove a face is live: the camera
/// picks the household member, and a fingerprint enrolled on the iPad unlocks that member's
/// personal content until they leave.
///
/// A fingerprint tells the app that someone who can unlock this iPad is present. It does not say
/// which person, so it is never offered for a profile picked by hand.
@MainActor
@Observable
public final class DeviceBiometricUnlock {
    /// The sensor this device can use. Refreshed when the app becomes active.
    public private(set) var biometry: DeviceBiometryKind
    public private(set) var isAuthenticating = false
    /// How the latest attempt ended.
    public private(set) var lastOutcome: DeviceBiometricUnlockOutcome?

    @ObservationIgnored private let session: HouseholdSession
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let service: FaceRecognitionService
    @ObservationIgnored private let authenticator: any DeviceBiometricAuthenticating
    @ObservationIgnored private let flow: DeviceBiometricUnlockFlow
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?

    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        service: FaceRecognitionService,
        authenticator: any DeviceBiometricAuthenticating = LocalAuthenticationAuthenticator()
    ) {
        self.session = session
        self.settings = settings
        self.service = service
        self.authenticator = authenticator
        self.flow = DeviceBiometricUnlockFlow(session: session, authenticator: authenticator)
        self.biometry = authenticator.biometryKind()
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBiometry() }
        }
    }

    isolated deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    /// Whether to show the Touch ID unlock right now: the setting is on, the device has Touch
    /// ID, no depth camera is in use, and a camera match is waiting.
    public var isOffered: Bool {
        flow.isOffered(
            settingEnabled: settings[FaceSettings.touchIDUnlock],
            biometry: biometry,
            hasDepthCamera: service.hasDepthCamera
        )
    }

    /// Reads the sensor state again. Runs by itself when the app becomes active, which also
    /// covers the return from the system prompt and from Settings.
    public func refreshBiometry() {
        let latest = authenticator.biometryKind()
        if biometry != latest {
            biometry = latest
        }
    }

    /// Shows the Touch ID prompt and, when a finger is accepted and the same camera match is
    /// still waiting, unlocks that member's personal content. Returns `.notAvailable` without a
    /// prompt when the unlock is not offered.
    @discardableResult
    public func unlock() async -> DeviceBiometricUnlockOutcome {
        guard !isAuthenticating else { return .notAvailable }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let name = session.cameraMatchedProfileID.flatMap { id in session.profiles.first { $0.id == id }?.name }
        let reason = name.map { String(localized: "Show personal content for \($0)") }
            ?? String(localized: "Show personal content")
        let outcome = await flow.unlock(
            settingEnabled: settings[FaceSettings.touchIDUnlock],
            biometry: biometry,
            hasDepthCamera: service.hasDepthCamera,
            reason: reason,
            at: Date()
        )
        lastOutcome = outcome
        if outcome == .lockedOut {
            refreshBiometry()
        }
        return outcome
    }
}

/// The Touch ID unlock button. It appears only while the unlock is offered and shows a short
/// message after a failed attempt.
public struct DeviceBiometricUnlockButton: View {
    private let unlock: DeviceBiometricUnlock

    @State private var failure: DeviceBiometricUnlockOutcome?

    public init(unlock: DeviceBiometricUnlock) {
        self.unlock = unlock
    }

    public var body: some View {
        if unlock.isOffered || failure != nil {
            VStack(spacing: 8) {
                if unlock.isOffered {
                    Button {
                        Task {
                            let outcome = await unlock.unlock()
                            failure = outcome.showsFailure ? outcome : nil
                        }
                    } label: {
                        Label {
                            Text("Unlock with Touch ID")
                        } icon: {
                            Image(systemName: "touchid")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(unlock.isAuthenticating)
                }
                if let failure {
                    Text(message(for: failure))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: failure)
            .task(id: failure) {
                guard failure != nil else { return }
                // The message is a hint, not a state. It goes away by itself.
                guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
                failure = nil
            }
        }
    }

    private func message(for outcome: DeviceBiometricUnlockOutcome) -> String {
        outcome == .lockedOut
            ? String(localized: "Touch ID is locked. Unlock the iPad with its passcode, then try again.")
            : String(localized: "Fingerprint not recognized. Try again.")
    }
}
