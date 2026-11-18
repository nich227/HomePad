import Foundation
import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadMessagingCore
import Observation
import SwiftUI
import UIKit

public enum HouseholdNoteSendOutcome: Sendable, Equatable {
    case sent
    /// Household notes are turned off in Settings on this device.
    case disabled
    case invalid(HouseholdNoteError)
    case nobodyConnected
}

/// Short household notes between the hub and companions. A hub shows an incoming note as a
/// banner; a companion shows it as a local notification. Notes are not stored.
@MainActor
@Observable
public final class HouseholdIntercom {
    /// The note to show as a banner on a hub.
    public private(set) var currentNote: HouseholdNote?

    @ObservationIgnored private let channel: any PeerChannel
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let session: HouseholdSession?
    @ObservationIgnored private let notifier: any HomePadNotifying
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var queue = NoteBannerQueue()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// Pass the `session` on a hub so a note carries the name of the member in front of it.
    public init(
        channel: any PeerChannel,
        settings: HomePadSettings,
        session: HouseholdSession? = nil,
        notifier: (any HomePadNotifying)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.channel = channel
        self.settings = settings
        self.session = session
        self.notifier = notifier ?? LocalNotifier()
        self.now = now
    }

    public var isEnabled: Bool { settings[MessagingSettings.householdNotes] }

    /// Starts listening. Safe to call more than once.
    public func start() {
        guard tasks.isEmpty else { return }
        let incoming = channel.messages(on: PeerChannelName.intercom)
        tasks.append(Task { [weak self] in
            for await envelope in incoming {
                await self?.receive(envelope)
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        queue = NoteBannerQueue()
        currentNote = nil
    }

    /// Sends a note to every connected peer.
    public func send(text: String) async -> HouseholdNoteSendOutcome {
        guard isEnabled else { return .disabled }
        let device = channel.localDevice
        let profile = device.role == .hub ? session?.activeProfile : session?.profiles.first { $0.id == device.profileID }
        let note: HouseholdNote
        let data: Data
        do {
            note = try HouseholdNoteCodec.make(
                id: UUID(),
                senderName: profile?.name ?? device.name,
                senderProfileID: profile?.id ?? device.profileID,
                text: text,
                sentAt: now()
            )
            data = try HouseholdNoteCodec.encode(note)
        } catch {
            return .invalid(error)
        }
        guard await !channel.connectedPeers().isEmpty else { return .nobodyConnected }
        do {
            try await channel.send(data, on: PeerChannelName.intercom, to: nil)
            return .sent
        } catch {
            return .nobodyConnected
        }
    }

    public func dismissCurrentNote() {
        queue.dismissCurrent(now: now())
        tick()
    }

    private func receive(_ envelope: PeerEnvelope) async {
        guard isEnabled, let note = try? HouseholdNoteCodec.decode(envelope.payload) else { return }
        if channel.localDevice.role == .hub {
            queue.enqueue(note, now: now())
            tick()
        } else {
            await notifier.postHouseholdNote(senderName: note.senderName, text: note.text, identifier: note.id.uuidString)
        }
    }

    private func tick() {
        let note = queue.current(now: now())
        if note != currentNote {
            currentNote = note
        }
    }
}

/// The hub's banner for an incoming household note. Place it as an overlay at the top of the hub.
public struct HouseholdNoteBanner: View {
    private let intercom: HouseholdIntercom
    private let proximity: Proximity

    public init(intercom: HouseholdIntercom, proximity: Proximity = .near) {
        self.intercom = intercom
        self.proximity = proximity
    }

    public var body: some View {
        let type = ProjectionType(proximity)
        ZStack {
            if let note = intercom.currentNote {
                HStack(spacing: 16) {
                    HomePadAnimationView(.listening)
                        .frame(width: type.symbolSize * 1.6, height: type.symbolSize * 1.6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.senderName).font(type.detail.weight(.semibold)).foregroundStyle(.secondary)
                        Text(note.text).font(type.body)
                    }
                    Spacer(minLength: 12)
                    Button {
                        intercom.dismissCurrentNote()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: type.symbolSize))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss note")
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Note from \(note.senderName): \(note.text)")
                .id(note.id)
            }
        }
        .animation(.snappy, value: intercom.currentNote?.id)
    }
}

/// A field for writing a household note, on either device.
public struct HouseholdNoteComposer: View {
    private let intercom: HouseholdIntercom
    @State private var text = ""
    @State private var outcome: HouseholdNoteSendOutcome?
    @State private var isSending = false

    public init(intercom: HouseholdIntercom) {
        self.intercom = intercom
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if intercom.isEnabled {
                HStack(spacing: 12) {
                    TextField("Note for the household", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Household note")
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send note")
                }
                Text("\(text.count) of \(HouseholdNoteCodec.maxTextLength) characters")
                    .font(.footnote)
                    .foregroundStyle(text.count > HouseholdNoteCodec.maxTextLength ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                if let outcome {
                    HStack(spacing: 8) {
                        if outcome == .sent {
                            HomePadAnimationView(.success, loop: false)
                                .frame(width: 32, height: 32)
                        }
                        Text(message(for: outcome)).font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("Household notes are turned off for this device.")
                    .foregroundStyle(.secondary)
                OpenSettingsButton()
            }
        }
    }

    private func send() async {
        isSending = true
        let result = await intercom.send(text: text)
        isSending = false
        outcome = result
        if result == .sent {
            text = ""
        }
    }

    private func message(for outcome: HouseholdNoteSendOutcome) -> String {
        switch outcome {
        case .sent: String(localized: "Note sent.")
        case .disabled: String(localized: "Household notes are turned off in Settings.")
        case .invalid(.textTooLong(let limit)): String(localized: "Keep the note under \(limit) characters.")
        case .invalid: String(localized: "Write something first.")
        case .nobodyConnected: String(localized: "No HomePad device is connected right now.")
        }
    }
}

/// Opens this app's page in the Settings app, where every HomePad preference lives.
public struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label("Open Settings", systemImage: "gear")
        }
        .accessibilityHint("Opens HomePad in the Settings app.")
    }
}
