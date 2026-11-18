import HomePadAnimations
import HomePadAnimationsCore
import HomePadBeamCore
import HomePadCore
import SwiftUI

/// The whole interface of the share extension: shows the page being shared, lists paired hubs,
/// sends, and reports what happened.
public struct BeamShareView: View {
    private let urlText: String
    private let title: String?
    private let onFinish: () -> Void

    @State private var model: Model

    /// - Parameters:
    ///   - defaults: The app group defaults, where the app mirrors the settings the extension
    ///     reads. The extension cannot see the app's own defaults.
    ///   - onFinish: Called when the person is done, to dismiss the extension.
    public init(url: URL, title: String?, defaults: UserDefaults, onFinish: @escaping () -> Void) {
        self.urlText = url.absoluteString
        self.title = title
        self.onFinish = onFinish
        self._model = State(initialValue: Model(defaults: defaults))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Beam to HomePad"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: finish)
                    }
                }
        }
        .onAppear { model.sender?.setSceneActive(true) }
        .onDisappear { model.sender?.setSceneActive(false) }
    }

    @ViewBuilder
    private var content: some View {
        if let sender = model.sender {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title {
                            Text(title).font(.headline)
                        }
                        Text(URL(string: urlText)?.host() ?? urlText)
                            .foregroundStyle(.secondary)
                    }
                    if case .failure(let reason) = sender.validate(urlText) {
                        Label(reason.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                Section("Send to") {
                    if sender.hubs.isEmpty {
                        Text("No hub is paired. Open HomePad on this iPhone and scan the pairing code shown on the hub.")
                    }
                    ForEach(sender.hubs) { hub in
                        Button {
                            Task { await sender.send(urlText, title: title, to: hub.id) }
                        } label: {
                            HStack {
                                Label(hub.device.name, systemImage: "ipad.landscape")
                                Spacer()
                                if !sender.isReachable(hub.id) {
                                    Text("Looking")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(sender.delivery == .sending || (try? sender.validate(urlText).get()) == nil)
                    }
                }
                if sender.delivery != .idle {
                    Section {
                        BeamDeliveryView(state: sender.delivery)
                        if sender.delivery != .sending {
                            Button("Done", action: finish)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Beam Is Not Available",
                systemImage: "lock.slash",
                description: Text("HomePad could not read its pairings. Unlock the iPhone, open HomePad once, and try again.")
            )
        }
    }

    private func finish() {
        model.sender?.setSceneActive(false)
        onFinish()
    }

    @MainActor
    private final class Model {
        let sender: BeamSender?

        init(defaults: UserDefaults) {
            let settings = HomePadSettings(defaults: defaults)
            settings.register(BeamSettings.descriptors)
            let store = KeychainPairingStore()
            guard let link = try? BeamEnvironment.makePeerLink(role: .companion, settings: settings, store: store) else {
                sender = nil
                return
            }
            let sender = BeamSender(link: link, settings: settings, store: store)
            sender.start()
            self.sender = sender
        }
    }
}
