import SwiftUI
import UIKit

/// Walks the person through creating the Shortcuts automation that relays incoming messages.
/// iOS has no API for an app to create a personal automation, so these steps are done by hand,
/// once, in the Shortcuts app.
public struct ShortcutsSetupGuideView: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    private struct Step: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let steps: [Step] = [
        Step(id: 1, title: "Open Shortcuts and choose Automation", detail: "Tap the Automation tab at the bottom, then tap the plus button to create a new automation."),
        Step(id: 2, title: "Choose Message", detail: "Scroll to Message. This is the trigger that runs when you get a message."),
        Step(id: 3, title: "Pick who and what", detail: "Choose a Sender, or type text under Message Contains. Shortcuts needs at least one of the two. To relay messages from several people, add them all as senders or repeat these steps for each person."),
        Step(id: 4, title: "Choose Run Immediately", detail: "Select Run Immediately and turn off Notify When Run, so messages are relayed without asking each time. Then tap Next."),
        Step(id: 5, title: "Add the HomePad action", detail: "Tap New Blank Automation, then Add Action. Search for Relay Message to HomePad and tap it."),
        Step(id: 6, title: "Fill in the action", detail: "Tap Message and choose Shortcut Input, which is the message. Tap Sender, choose Shortcut Input, then tap it again and pick Sender. If you want replies to open with the right person filled in, expand the action and set Phone or Email the same way."),
        Step(id: 7, title: "Tap Done", detail: "Send yourself a message from another device to test. It appears on HomePad when HomePad recognizes you."),
    ]

    public var body: some View {
        List {
            Section {
                Text("HomePad cannot read your messages. Instead, the Shortcuts app can hand each new message to HomePad as it arrives. You set this up once.")
            }
            Section("Steps") {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(step.id, format: .number)
                            .font(.headline)
                            .monospacedDigit()
                            .frame(minWidth: 28, minHeight: 28)
                            .background(.tint.opacity(0.15), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.headline)
                            Text(step.detail).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Step \(step.id)"))
                    .accessibilityValue(Text("\(Text(step.title)). \(Text(step.detail))"))
                }
            }
            Section {
                Button {
                    if let url = URL(string: "shortcuts://") {
                        openURL(url)
                    }
                } label: {
                    Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                }
                .accessibilityHint("Opens the Shortcuts app so you can create the automation.")
            } footer: {
                Text("Good to know: only messages that arrive while this automation is on are relayed, and only while HomePad is open on this iPhone and a HomePad is nearby. iOS can turn an automation off after an update, so check here if messages stop appearing. Relayed messages are kept in memory only and are never saved on HomePad.")
            }
        }
        .navigationTitle("Relay Messages")
    }
}
