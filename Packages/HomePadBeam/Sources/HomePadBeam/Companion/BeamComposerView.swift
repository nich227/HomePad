import HomePadAnimations
import HomePadAnimationsCore
import HomePadBeamCore
import HomePadCore
import SwiftUI
import UIKit

/// The companion's beam screen: type or paste an address, pick a hub, send. Also where an iPhone
/// is paired with a hub and where paired hubs are listed.
public struct BeamComposerView<Accessory: View>: View {
    private let sender: BeamSender
    private let accessory: (URL) -> Accessory

    @State private var text = ""
    @State private var hubID: UUID?
    @State private var isScanning = false
    @State private var typedCode = ""
    @Environment(\.openURL) private var openURL

    /// - Parameter accessory: Extra actions for a valid address, such as `SharePlayButton`.
    public init(sender: BeamSender, @ViewBuilder accessory: @escaping (URL) -> Accessory = { _ in EmptyView() }) {
        self.sender = sender
        self.accessory = accessory
    }

    private var validated: ValidatedURL? {
        try? sender.validate(text).get()
    }

    public var body: some View {
        Form {
            if let incoming = sender.incoming {
                Section("From the hub") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(incoming.title ?? incoming.url.host() ?? "")
                            .font(.headline)
                        Text(incoming.url.host() ?? "")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open") {
                                openURL(incoming.url)
                                sender.dismissIncoming()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Dismiss", role: .cancel) { sender.dismissIncoming() }
                        }
                    }
                }
            }

            Section {
                TextField(text: $text, prompt: Text("example.com")) {
                    Text("Web address")
                }
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(send)
                .onChange(of: text) { sender.resetDelivery() }
                Button("Paste", systemImage: "doc.on.clipboard") {
                    if let pasted = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string {
                        text = pasted
                    }
                }
                if sender.hubs.count > 1 {
                    Picker(selection: $hubID) {
                        ForEach(sender.hubs) { hub in
                            Text(hub.device.name).tag(UUID?.some(hub.id))
                        }
                    } label: {
                        Text("Send to")
                    }
                }
            } header: {
                Text("Beam a page")
            } footer: {
                if !text.isEmpty, case .failure(let reason) = sender.validate(text) {
                    Text(reason.message)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: send) {
                    Label("Send to Hub", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(validated == nil || sender.hubs.isEmpty || sender.delivery == .sending)
                .listRowBackground(Color.clear)
                if let url = validated?.url {
                    accessory(url)
                }
                BeamDeliveryView(state: sender.delivery)
            }

            pairingSection

            if sender.linkStatus.snapshot.isLocalNetworkDenied {
                Section {
                    Label("HomePad is not allowed to use the local network, so it cannot find your hub.", systemImage: "wifi.exclamationmark")
                    OpenSettingsButton(title: "Open Settings")
                }
            }
        }
        .navigationTitle(Text("Beam"))
        .beamHandoffAdvertising(urlText: text, title: nil, isEnabled: sender.preferences.handoffEnabled)
        .onAppear { hubID = hubID ?? sender.hubs.first?.id }
        .onChange(of: sender.hubs.map(\.id)) { _, ids in
            if let hubID, ids.contains(hubID) { return }
            hubID = ids.first
        }
        .sheet(isPresented: $isScanning) {
            scannerSheet
        }
    }

    private func send() {
        guard validated != nil else { return }
        Task { await sender.send(text, title: nil, to: hubID) }
    }

    private var pairingSection: some View {
        Section {
            ForEach(sender.hubs) { hub in
                HStack {
                    Image(systemName: "ipad.landscape")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(hub.device.name)
                        Text(sender.isReachable(hub.id) ? "Nearby" : "Not found on this network")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Forget", systemImage: "trash", role: .destructive) { sender.forget(hub.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Forget \(hub.device.name)"))
                }
            }
            Button("Scan Pairing Code", systemImage: "qrcode.viewfinder") {
                sender.resetPairing()
                isScanning = true
            }
            pairingStatus
        } header: {
            Text("Hubs")
        } footer: {
            Text("To pair, open HomePad on the iPad, turn on Setup Mode in Settings, and show the pairing code.")
        }
    }

    @ViewBuilder
    private var pairingStatus: some View {
        switch sender.pairingState {
        case .idle:
            EmptyView()
        case .pairing:
            HStack {
                HomePadAnimationView(.pairing)
                    .frame(width: 44, height: 44)
                Text("Pairing")
            }
        case .paired(let hub):
            HStack {
                HomePadAnimationView(.success, loop: false)
                    .frame(width: 44, height: 44)
                Text("Paired with \(hub.name)")
            }
        case .invalidCode(.expired):
            Label("That code has expired. Show a new one on the hub.", systemImage: "clock.badge.exclamationmark")
        case .invalidCode:
            Label("That is not a HomePad pairing code.", systemImage: "qrcode")
        case .failed(.hubNotFound):
            Label("The hub was not found. Keep the pairing code on screen and make sure both devices are on the same network.", systemImage: "wifi.exclamationmark")
        case .failed:
            Label("Pairing did not finish. Show a new code on the hub and try again.", systemImage: "exclamationmark.triangle")
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            Group {
                if QRScannerView.isUsable {
                    QRScannerView { code in
                        isScanning = false
                        Task { await sender.pair(code: code) }
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    Form {
                        Section {
                            Text("The camera is not available. Point the Camera app at the hub's code instead, or paste the pairing link here.")
                            TextField(text: $typedCode) {
                                Text("Pairing link")
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button("Pair") {
                                isScanning = false
                                Task { await sender.pair(code: typedCode) }
                            }
                            .disabled(typedCode.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle(Text("Scan Pairing Code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isScanning = false }
                }
            }
        }
    }
}

/// Shows where a sent page is: on its way, delivered, or failed.
struct BeamDeliveryView: View {
    let state: BeamDeliveryState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 12) {
                HomePadAnimationView(.beamSending)
                    .frame(width: 56, height: 56)
                Text("Sending")
            }
            .accessibilityElement(children: .combine)
        case .delivered(let outcome):
            HStack(spacing: 12) {
                if state.isSuccess {
                    HomePadAnimationView(.success, loop: false)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .font(.title)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(outcome.message)
            }
            .accessibilityElement(children: .combine)
        case .failed(let error):
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
