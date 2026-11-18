import HomePadKioskCore
import SwiftUI

/// The kiosk lock's only in-app surface: a lock button while the iPad is locked to HomePad, a
/// countdown while it is released, and a hint when the lock cannot engage.
public struct KioskLockOverlay: View {
    private let controller: KioskLockController
    private let showsHints: Bool

    /// - Parameter showsHints: show why the lock is not engaged. Pass the Setup Mode setting.
    public init(controller: KioskLockController, showsHints: Bool) {
        self.controller = controller
        self.showsHints = showsHints
    }

    public var body: some View {
        Group {
            switch controller.state {
            case .locked(.singleAppMode), .authenticating, .releasing:
                Button {
                    controller.requestUnlock()
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(controller.state != .locked(.singleAppMode))
                .accessibilityLabel(Text("Unlock to leave HomePad"))
                .accessibilityHint(Text("Asks for the iPad passcode"))

            case .locked(.guidedAccess):
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .accessibilityLabel(Text("Guided Access is on"))

            case .released(let deadline):
                capsule(systemImage: "lock.open.fill") {
                    Text("Unlocked. Locks again in \(Text(deadline, style: .timer).monospacedDigit())")
                }

            case .unavailable(.noPasscode) where showsHints:
                capsule(systemImage: "exclamationmark.lock.fill") {
                    Text("Set an iPad passcode to use Kiosk Lock.")
                }

            case .unavailable(.notPermitted) where showsHints:
                capsule(systemImage: "exclamationmark.lock.fill") {
                    Text("This iPad does not let HomePad lock itself. Triple-click the top button to start Guided Access.")
                }

            case .off, .engaging, .unavailable:
                EmptyView()
            }
        }
        .animation(.snappy, value: controller.state)
    }

    private func capsule(systemImage: String, @ViewBuilder text: () -> Text) -> some View {
        Label {
            text()
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
