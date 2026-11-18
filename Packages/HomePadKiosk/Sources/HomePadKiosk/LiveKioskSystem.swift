import HomePadKioskCore
import LocalAuthentication
import Security
import UIKit

/// Single App Mode through UIKit and a passcode-only prompt through LocalAuthentication.
@MainActor
public final class LiveKioskSystem: KioskSystem {
    private let unlockReason: String

    public init(unlockReason: String = String(localized: "Enter the iPad passcode to leave HomePad.")) {
        self.unlockReason = unlockReason
    }

    public var isGuidedAccessActive: Bool {
        UIAccessibility.isGuidedAccessEnabled
    }

    public var isPasscodeSet: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public func setSingleAppMode(_ enabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            UIAccessibility.requestGuidedAccessSession(enabled: enabled) { succeeded in
                continuation.resume(returning: succeeded)
            }
        }
    }

    public func verifyPasscode() async -> PasscodeOutcome {
        // The devicePasscode flag makes the prompt accept the passcode only, never Face ID or
        // Touch ID, so a household member whose face unlocks the iPad still cannot leave.
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, nil
        ) else {
            return .rejected
        }
        do {
            try await LAContext().evaluateAccessControl(accessControl, operation: .useItem, localizedReason: unlockReason)
            return .accepted
        } catch let error as LAError where error.code == .passcodeNotSet {
            return .notSet
        } catch {
            return .rejected
        }
    }

    public func guidedAccessChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let name = UIAccessibility.guidedAccessStatusDidChangeNotification
                for await _ in NotificationCenter.default.notifications(named: name).map({ _ in () }) {
                    continuation.yield(UIAccessibility.isGuidedAccessEnabled)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
