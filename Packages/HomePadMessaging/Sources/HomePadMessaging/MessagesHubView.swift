import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadMessagingCore
import SwiftUI
import UIKit

/// The hub's Messages app: the active member's relayed conversations, projected from their iPhone,
/// with a reply field. A reply is never sent from here directly; the field shows where the person
/// will confirm it.
public struct MessagesHubView: View {
    private let client: ProjectionClient
    private let session: HouseholdSession

    @State private var draft = ""
    @State private var handedOffTo: String?
    @State private var hubCompose: HubCompose?
    @FocusState private var isReplyFocused: Bool

    private struct HubCompose: Identifiable {
        let id = UUID()
        let recipients: [String]
        let body: String
    }

    public init(client: ProjectionClient, session: HouseholdSession) {
        self.client = client
        self.session = session
    }

    private var entry: ProjectedAppEntry? {
        client.entries.first { $0.app.id == BuiltInProjectedApp.messagesID && $0.ownerProfileID == session.activeProfile?.id }
    }

    public var body: some View {
        let type = ProjectionType(session.proximity)
        Group {
            if let entry {
                content(for: entry, type: type)
            } else if session.activeProfile == nil {
                unavailable(
                    type: type,
                    title: "Messages Are Personal",
                    message: "Messages appear when HomePad recognizes a household member whose iPhone is nearby."
                )
            } else {
                noMessagesFromPhone(type: type)
            }
        }
        .sheet(item: $hubCompose) { compose in
            MessageComposer(recipients: compose.recipients, body: compose.body) { outcome in
                hubCompose = nil
                if outcome == .sent {
                    draft = ""
                }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(for entry: ProjectedAppEntry, type: ProjectionType) -> some View {
        switch client.content(for: entry.id, depth: 1) {
        case .redacted(let reason):
            RedactedPlaceholderView(app: entry.app, reason: reason, proximity: session.proximity)
        case .loading:
            ProgressView("Waiting for your iPhone")
                .font(type.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            noMessagesFromPhone(type: type)
        case .template(let root, _, _):
            HStack(spacing: 0) {
                sidebar(root, entry: entry, type: type)
                    .frame(maxWidth: session.proximity == .far ? 520 : 380)
                Divider()
                detail(entry: entry, type: type)
            }
        }
    }

    // MARK: Conversation list

    @ViewBuilder
    private func sidebar(_ root: ProjectionTemplate, entry: ProjectedAppEntry, type: ProjectionType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(root.title)
                .font(type.title)
                .padding([.horizontal, .top], 24)
                .accessibilityAddTraits(.isHeader)
            if case .conversationList(let list) = root, !list.conversations.isEmpty {
                let selected = selectedConversation(in: entry)?.conversationID
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(list.conversations) { conversation in
                            Button {
                                handedOffTo = nil
                                draft = ""
                                client.perform(actionID: conversation.actionID, in: entry.id)
                            } label: {
                                ConversationRow(conversation: conversation, type: type, isSelected: conversation.id == selected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(conversation.id == selected ? .isSelected : [])
                        }
                    }
                    .padding(12)
                }
            } else {
                ProjectionTemplateView(template: root, proximity: session.proximity) { actionID, payload in
                    client.perform(actionID: actionID, payload: payload, in: entry.id)
                }
            }
        }
    }

    private func selectedConversation(in entry: ProjectedAppEntry) -> ConversationTemplate? {
        guard case .template(.conversation(let conversation), _, _) = client.content(for: entry.id, depth: 2) else { return nil }
        return conversation
    }

    // MARK: Conversation and reply

    @ViewBuilder
    private func detail(entry: ProjectedAppEntry, type: ProjectionType) -> some View {
        if let conversation = selectedConversation(in: entry) {
            VStack(spacing: 0) {
                Text(conversation.title)
                    .font(type.body.weight(.semibold))
                    .padding(16)
                    .accessibilityAddTraits(.isHeader)
                Divider()
                ConversationBubblesView(template: conversation, type: type)
                Divider()
                replyBar(for: conversation, entry: entry, type: type)
            }
        } else {
            Text("Choose a conversation")
                .font(type.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func replyBar(for conversation: ConversationTemplate, entry: ProjectedAppEntry, type: ProjectionType) -> some View {
        let route = client.replyRoute(for: entry.id, canReply: conversation.canReply, hubCanSendText: MessageComposer.canSendText)
        VStack(alignment: .leading, spacing: 10) {
            if let handedOffTo {
                HStack(spacing: 12) {
                    HomePadAnimationView(.success, loop: false)
                        .frame(width: 44, height: 44)
                    Text("Reply sent to \(handedOffTo). Review it there and tap Send.")
                        .font(type.detail)
                }
                .accessibilityElement(children: .combine)
            }
            if case .unavailable = route {
                EmptyView()
            } else {
                HStack(spacing: 12) {
                    TextField("Reply", text: $draft, axis: .vertical)
                        .font(type.body)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($isReplyFocused)
                        .accessibilityLabel("Reply to \(conversation.title)")
                    Button {
                        submit(route: route, conversation: conversation, entry: entry)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: type.symbolSize * 1.3))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(route == .composeOnHub ? Text("Review and send") : Text("Send to iPhone for review"))
                }
            }
            Text(explanation(for: route, entry: entry))
                .font(type.detail)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func submit(route: ReplyRoute, conversation: ConversationTemplate, entry: ProjectedAppEntry) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines).projectionTruncated(to: ProjectionLimits.standard.maxBodyLength)
        guard !text.isEmpty else { return }
        switch route {
        case .composeOnHub:
            hubCompose = HubCompose(recipients: conversation.recipientHandle.map { [$0] } ?? [], body: text)
        case .handOffToCompanion:
            client.sendReply(conversationID: conversation.conversationID, text: text, in: entry.id)
            handedOffTo = entry.deviceName
            draft = ""
            isReplyFocused = false
        case .unavailable:
            break
        }
    }

    private func explanation(for route: ReplyRoute, entry: ProjectedAppEntry) -> String {
        switch route {
        case .composeOnHub:
            String(localized: "You will review the message on this iPad and send it from the Messages account signed in here.")
        case .handOffToCompanion:
            String(localized: "Your reply goes to \(entry.deviceName). Nothing is sent until you tap Send there.")
        case .unavailable(.personalContentLocked):
            String(localized: "Replies are available when HomePad recognizes you.")
        case .unavailable(.conversationReadOnly):
            String(localized: "This conversation cannot be replied to from HomePad.")
        case .unavailable(.companionNotConnected):
            String(localized: "Your iPhone is not connected, so a reply cannot be sent from HomePad right now.")
        }
    }

    private func noMessagesFromPhone(type: ProjectionType) -> some View {
        unavailable(
            type: type,
            title: "No Messages from Your iPhone",
            message: "Open HomePad on your iPhone nearby. Messages show here after you set up the message relay there."
        )
    }

    private func unavailable(type: ProjectionType, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: type.rowSpacing) {
            Image(systemName: "message.fill")
                .font(.system(size: type.symbolSize * 1.6))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(type.title)
            Text(message).font(type.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
