import Foundation
import Intents
import UserNotifications

/// Posts local notifications on a companion. Notification text is never logged.
@MainActor
public protocol HomePadNotifying: AnyObject {
    /// A reply typed on the hub is waiting for its owner to review and send.
    func postPendingReply(recipientName: String, identifier: String) async
    func postHouseholdNote(senderName: String, text: String, identifier: String) async
    func removeDelivered(identifier: String)
}

@MainActor
public final class LocalNotifier: HomePadNotifying {
    public static let pendingReplyCategory = "homepad.pendingReply"
    public static let householdNoteCategory = "homepad.householdNote"

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Asks for permission the first time. Returns whether notifications may be shown.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func postPendingReply(recipientName: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Reply from HomePad")
        content.body = String(localized: "Tap to review and send your reply to \(recipientName).")
        content.sound = .default
        content.categoryIdentifier = Self.pendingReplyCategory
        await post(content, identifier: identifier)
    }

    public func postHouseholdNote(senderName: String, text: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = senderName
        content.body = text
        content.sound = .default
        content.categoryIdentifier = Self.householdNoteCategory
        content.threadIdentifier = Self.householdNoteCategory
        await post(communicationContent(from: content, senderName: senderName, text: text), identifier: identifier)
    }

    public func removeDelivered(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func post(_ content: UNNotificationContent, identifier: String) async {
        guard await requestAuthorization() else { return }
        // A notification that cannot be scheduled is not worth surfacing; the content stays in the app.
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Styles the note as a message from a person. This needs the Communication Notifications
    /// capability and `INSendMessageIntent` in `NSUserActivityTypes`; without them the system
    /// refuses the update and the plain content is used.
    private func communicationContent(from content: UNNotificationContent, senderName: String, text: String) async -> UNNotificationContent {
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderName, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: nil
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: text,
            speakableGroupName: nil,
            conversationIdentifier: Self.householdNoteCategory,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            return try content.updating(from: intent)
        } catch {
            return content
        }
    }
}
