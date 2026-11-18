import HomePadAnimations
import HomePadAnimationsCore
import HomePadBeamCore
import HomePadCore
import SwiftUI

/// The hub's pairing screen: shows a QR code for one iPhone at a time, and lists paired iPhones
/// with a way to remove each. Pairing is a setup task; nothing here changes a preference.
public struct PairingView: View {
    private let receiver: BeamReceiver
    private let session: HouseholdSession

    @State private var profileID: UUID?
    @State private var deviceToRevoke: PairedDevice?

    public init(receiver: BeamReceiver, session: HouseholdSession) {
        self.receiver = receiver
        self.session = session
    }

    public var body: some View {
        List {
            Section {
                if let invitation = receiver.invitation {
                    invitationView(invitation)
                } else if let paired = receiver.lastPairedDevice {
                    pairedView(paired)
                } else {
                    startView
                }
            } footer: {
                Text("The code works once, for one iPhone, and expires after two minutes. Anyone who can see it while it is on screen can pair, so close it when you are done.")
            }

            if !receiver.preferences.receiveBeams {
                Section {
                    Label("Receive Beams is off in Settings. Paired iPhones cannot send pages until it is on.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    OpenSettingsButton(title: "Open Settings")
                }
            }
            if receiver.linkStatus.snapshot.isLocalNetworkDenied {
                Section {
                    Label("HomePad is not allowed to use the local network, so iPhones cannot find this hub.", systemImage: "wifi.exclamationmark")
                    OpenSettingsButton(title: "Open Settings")
                }
            }

            Section("Paired iPhones") {
                if receiver.pairedDevices.isEmpty {
                    Text("No iPhones are paired yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(receiver.pairedDevices) { device in
                    deviceRow(device)
                }
            }
        }
        .navigationTitle(Text("Pair an iPhone"))
        .onDisappear { receiver.closePairing() }
        .confirmationDialog(
            Text("Remove this iPhone?"),
            isPresented: Binding(get: { deviceToRevoke != nil }, set: { if !$0 { deviceToRevoke = nil } }),
            titleVisibility: .visible,
            presenting: deviceToRevoke
        ) { device in
            Button("Remove", role: .destructive) { receiver.revoke(device.id) }
            Button("Cancel", role: .cancel) {}
        } message: { device in
            Text("\(device.device.name) will no longer be able to connect to this hub. Other iPhones stay paired.")
        }
    }

    private var startView: some View {
        VStack(spacing: 16) {
            HomePadAnimationView(.pairing, loop: true, isPlaying: false)
                .frame(height: 140)
            if !session.profiles.isEmpty {
                Picker(selection: $profileID) {
                    Text("Nobody in particular").tag(UUID?.none)
                    ForEach(session.profiles) { profile in
                        Text(profile.name).tag(UUID?.some(profile.id))
                    }
                } label: {
                    Text("Whose iPhone is it?")
                }
            }
            Button {
                receiver.openPairing(for: profileID)
            } label: {
                Label("Show Pairing Code", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }

    private func invitationView(_ invitation: PairingInvitation) -> some View {
        VStack(spacing: 16) {
            QRCodeView(text: invitation.code)
                .frame(maxWidth: 360)
            HomePadAnimationView(.pairing)
                .frame(height: 72)
            Text("On the iPhone, open HomePad and choose Scan Pairing Code, or point the Camera at this code.")
                .font(.title3)
                .multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = receiver.pairingSecondsRemaining(at: context.date)
                Text("Expires in \(remaining) seconds")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 15 ? .red : .secondary)
                    .onChange(of: remaining) { _, value in
                        if value <= 0 { receiver.refreshPairing() }
                    }
            }
            Button("Hide Code", role: .cancel) { receiver.closePairing() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func pairedView(_ paired: PairedDevice) -> some View {
        VStack(spacing: 12) {
            HomePadAnimationView(.success, loop: false)
                .frame(height: 140)
            Text("\(paired.device.name) is paired")
                .font(.title2.weight(.semibold))
            Button("Pair Another iPhone") { receiver.openPairing(for: profileID) }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func deviceRow(_ device: PairedDevice) -> some View {
        let owner = session.profiles.first { $0.id == device.device.profileID }
        let isConnected = receiver.linkStatus.snapshot.connectedPeers.contains { $0.id == device.id }
        return HStack {
            Image(systemName: "iphone")
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(device.device.name)
                Group {
                    if let owner {
                        Text("\(owner.name), paired \(device.pairedAt, format: .dateTime.month().day().year())")
                    } else {
                        Text("Paired \(device.pairedAt, format: .dateTime.month().day().year())")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isConnected {
                Text("Connected")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Button("Remove", systemImage: "trash", role: .destructive) { deviceToRevoke = device }
                .labelStyle(.iconOnly)
                .accessibilityLabel(Text("Remove \(device.device.name)"))
        }
    }
}
