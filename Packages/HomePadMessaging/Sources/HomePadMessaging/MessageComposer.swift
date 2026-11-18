import HomePadMessagingCore
import MessageUI
import SwiftUI
import UIKit

/// The system message sheet, prefilled. The person always reviews the message and taps Send;
/// nothing here can send on its own.
public struct MessageComposer: UIViewControllerRepresentable {
    public enum Outcome: Sendable, Equatable {
        case sent, cancelled, failed
    }

    /// False on a device that cannot send messages, such as an iPad without iMessage set up.
    public static var canSendText: Bool {
        MFMessageComposeViewController.canSendText()
    }

    private let recipients: [String]
    private let messageBody: String
    private let attachmentURL: URL?
    private let onFinish: @MainActor (Outcome) -> Void

    /// A web `attachmentURL` is added to the end of the text. A file URL is attached when the
    /// device allows attachments.
    public init(
        recipients: [String],
        body: String,
        attachmentURL: URL? = nil,
        onFinish: @escaping @MainActor (Outcome) -> Void
    ) {
        self.recipients = recipients
        self.messageBody = body
        self.attachmentURL = attachmentURL
        self.onFinish = onFinish
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        guard Self.canSendText else {
            return UIHostingController(rootView: MessagingUnavailableView())
        }
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients.isEmpty ? nil : recipients
        var text = messageBody
        if let attachmentURL {
            if attachmentURL.isFileURL {
                if MFMessageComposeViewController.canSendAttachments() {
                    controller.addAttachmentURL(attachmentURL, withAlternateFilename: nil)
                }
            } else {
                text = text.isEmpty ? attachmentURL.absoluteString : text + "\n" + attachmentURL.absoluteString
            }
        }
        controller.body = text
        return controller
    }

    public func updateUIViewController(_ controller: UIViewController, context: Context) {}

    @MainActor
    public final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: @MainActor (Outcome) -> Void

        init(onFinish: @escaping @MainActor (Outcome) -> Void) {
            self.onFinish = onFinish
        }

        public nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            let outcome: Outcome = switch result {
            case .sent: .sent
            case .cancelled: .cancelled
            case .failed: .failed
            @unknown default: .failed
            }
            // MessageUI calls its delegate on the main thread, but the protocol does not say so.
            MainActor.assumeIsolated { onFinish(outcome) }
        }
    }
}

struct MessagingUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label("Messages Is Not Set Up", systemImage: "message.badge.waveform")
        } description: {
            Text("This device cannot send messages. Turn on iMessage in Settings, or send the reply from your iPhone.")
        } actions: {
            Button("Close") { dismiss() }
        }
    }
}

extension View {
    /// Presents the message sheet on the companion for each reply that arrived from a hub. Attach
    /// it to the companion's root view. The reply is sent only if the person taps Send.
    public func homePadReplyComposer(host: ProjectionHost) -> some View {
        modifier(ReplyComposerModifier(messages: host.messages))
    }
}

private struct ReplyComposerModifier: ViewModifier {
    let messages: MessagesAppProvider

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { messages.pendingReply }, set: { _ in })) { reply in
            MessageComposer(
                recipients: reply.recipientHandle.map { [$0] } ?? [],
                body: reply.text.reveal()
            ) { outcome in
                messages.finish(reply, sent: outcome == .sent)
            }
            .ignoresSafeArea()
            .interactiveDismissDisabled()
            .onDisappear {
                // The unavailable screen closes without a compose result.
                if messages.pendingReply?.id == reply.id, !MessageComposer.canSendText {
                    messages.finish(reply, sent: false)
                }
            }
        }
    }
}
