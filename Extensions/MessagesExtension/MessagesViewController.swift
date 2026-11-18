import HomePadCore
import HomePadMessagingCore
import Messages
import Observation
import SwiftUI
import UIKit

/// What the extension shows. The decisions (link encoding, validation, what is offered) live in
/// HomePadMessagingCore; this type only holds the results for the view.
@MainActor
@Observable
final class MessagesExtensionModel {
    var recentPages: [RecentPage] = []
    var hubItem: SharedHubItem?
    /// Set when the selected message in the conversation carries a HomePad link.
    var received: ReceivedLink?
    var isExpanded = false
    var notice: String?

    struct ReceivedLink: Equatable {
        let link: MessageDeepLink
        let appURL: URL
    }

    func reload(from store: MessagesExtensionStore, selectedMessageURL: URL?, now: Date = Date()) {
        recentPages = store.recentPages()
        hubItem = store.hubItem(now: now)
        select(messageURL: selectedMessageURL)
    }

    func select(messageURL: URL?) {
        received = MessagesExtensionLogic.openAction(forMessageURL: messageURL).map { ReceivedLink(link: $0.link, appURL: $0.appURL) }
    }
}

/// The iMessage app. It sends HomePad links as interactive messages and opens received ones in
/// the HomePad app. It cannot read the conversation, and it never sends anything by itself: an
/// inserted message waits in the input field for the person to send.
final class MessagesViewController: MSMessagesAppViewController {
    private let model = MessagesExtensionModel()
    // The app mirrors what the extension needs into the app group. Without the group the store is empty.
    private let store = MessagesExtensionStore(defaults: UserDefaults(suiteName: HomePadIdentifiers.appGroup) ?? .standard)

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = MessagesExtensionView(
            model: model,
            onSendPage: { [weak self] url, title in self?.insert(.beamPage(url), title: title) },
            onShareHubItem: { [weak self] item in self?.insertHubItem(item) },
            onOpen: { [weak self] url in self?.openContainingApp(url) },
            onExpand: { [weak self] in self?.requestPresentationStyle(.expanded) }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        model.isExpanded = presentationStyle == .expanded
        model.reload(from: store, selectedMessageURL: conversation.selectedMessage?.url)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        model.select(messageURL: message.url)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        model.isExpanded = presentationStyle == .expanded
    }

    // MARK: Actions

    private func insertHubItem(_ item: SharedHubItem) {
        guard let link = try? MessageDeepLinkCodec.decode(item.link) else {
            model.notice = String(localized: "That item can no longer be shared.")
            return
        }
        insert(link, title: item.title)
    }

    private func insert(_ link: MessageDeepLink, title: String?) {
        guard let conversation = activeConversation,
              let card = try? MessagesExtensionLogic.card(for: link, title: title)
        else {
            model.notice = String(localized: "That link cannot be sent to a HomePad.")
            return
        }
        let layout = MSMessageTemplateLayout()
        layout.caption = card.caption
        layout.subcaption = card.subcaption
        layout.trailingCaption = String(localized: "HomePad")
        layout.image = UIImage(systemName: card.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 120, weight: .regular))

        let message = MSMessage(session: conversation.selectedMessage?.session ?? MSSession())
        message.layout = layout
        message.url = card.messageURL
        message.summaryText = String(localized: "Open \(card.caption) on HomePad")
        message.accessibilityLabel = message.summaryText

        conversation.insert(message) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.model.notice = String(localized: "The message could not be added. Try again.")
            }
        }
        requestPresentationStyle(.compact)
    }

    private func openContainingApp(_ url: URL) {
        extensionContext?.open(url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.model.notice = String(localized: "HomePad could not be opened.")
            }
        }
    }
}

// MARK: View

struct MessagesExtensionView: View {
    let model: MessagesExtensionModel
    let onSendPage: (URL, String?) -> Void
    let onShareHubItem: (SharedHubItem) -> Void
    let onOpen: (URL) -> Void
    let onExpand: () -> Void

    @State private var typedAddress = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let received = model.received {
                    receivedSection(received)
                }
                sendPageSection
                if let hubItem = model.hubItem {
                    Button {
                        onShareHubItem(hubItem)
                    } label: {
                        Label("Share what's on my HomePad", systemImage: "rectangle.on.rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Adds \(hubItem.title) to the message field."))
                }
                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func receivedSection(_ received: MessagesExtensionModel.ReceivedLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(description(of: received.link))
                .font(.headline)
            Button {
                onOpen(received.appURL)
            } label: {
                Label("Open on HomePad", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens the HomePad app, which shows this on a nearby HomePad.")
        }
    }

    private var sendPageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send a page to a HomePad")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        sendPage(fromText: strings.first)
                    }
                }
                .labelStyle(.titleAndIcon)
                if !model.isExpanded {
                    Button("Type an Address", systemImage: "keyboard", action: onExpand)
                        .buttonStyle(.bordered)
                }
            }
            if model.isExpanded {
                HStack(spacing: 10) {
                    TextField("example.com", text: $typedAddress)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit { sendPage(fromText: typedAddress) }
                        .accessibilityLabel("Web address")
                    Button("Add") { sendPage(fromText: typedAddress) }
                        .buttonStyle(.borderedProminent)
                        .disabled(MessagesExtensionLogic.pageURL(fromText: typedAddress) == nil)
                }
            }
            if !model.recentPages.isEmpty {
                Text("Recent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.recentPages) { page in
                    Button {
                        onSendPage(page.url, page.title)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title ?? page.url.host() ?? page.url.absoluteString)
                                .lineLimit(1)
                            Text(page.url.host() ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sendPage(fromText text: String?) {
        guard let url = MessagesExtensionLogic.pageURL(fromText: text) else {
            model.notice = String(localized: "That does not look like a web address.")
            return
        }
        model.notice = nil
        typedAddress = ""
        onSendPage(url, nil)
    }

    private func description(of link: MessageDeepLink) -> String {
        switch link {
        case .beamPage(let page):
            String(localized: "A page from \(page.host() ?? page.absoluteString)")
        case .openApp:
            String(localized: "A HomePad app")
        case .openFace:
            String(localized: "A HomePad face")
        }
    }
}
