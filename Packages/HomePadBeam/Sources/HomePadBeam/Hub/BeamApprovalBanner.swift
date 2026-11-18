import HomePadAnimations
import HomePadAnimationsCore
import HomePadBeamCore
import HomePadCore
import SwiftUI

/// Asks whoever is at the hub whether to open the oldest waiting page. Shows who sent it and the
/// site it points to, sized to be read from across the room when nobody is near.
public struct BeamApprovalBanner: View {
    private let receiver: BeamReceiver
    private let proximity: Proximity

    public init(receiver: BeamReceiver, proximity: Proximity) {
        self.receiver = receiver
        self.proximity = proximity
    }

    public var body: some View {
        if let beam = receiver.pending.first {
            let isFar = proximity == .far
            HStack(spacing: 20) {
                HomePadAnimationView(.beamIncoming, loop: false)
                    .frame(width: isFar ? 120 : 72, height: isFar ? 120 : 72)
                    .id(beam.id)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(beam.sender.name) sent a page")
                        .font(isFar ? .largeTitle.weight(.semibold) : .title2.weight(.semibold))
                    Text(beam.url.host() ?? beam.url.absoluteString)
                        .font(isFar ? .title : .title3)
                        .foregroundStyle(.secondary)
                    if let title = beam.title, !isFar {
                        Text(title)
                            .font(.body)
                            .lineLimit(2)
                    }
                    if receiver.pending.count > 1 {
                        Text("\(receiver.pending.count - 1) more waiting")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 12) {
                    Button {
                        receiver.approve(beam.id)
                    } label: {
                        Label("Open", systemImage: "safari")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not Now", role: .cancel) { receiver.decline(beam.id) }
                        .buttonStyle(.bordered)
                }
                .controlSize(isFar ? .extraLarge : .large)
            }
            .padding(24)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Incoming page"))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Pages opened on the hub recently. Tapping one opens it again.
public struct BeamRecentsView: View {
    private let receiver: BeamReceiver

    public init(receiver: BeamReceiver) {
        self.receiver = receiver
    }

    public var body: some View {
        Group {
            if receiver.preferences.keepHistory, receiver.recents.isEmpty {
                // Outside the list, so it fills the screen instead of sitting in one row.
                ContentUnavailableView(
                    "No Recent Pages",
                    systemImage: "clock",
                    description: Text("Pages sent from a paired iPhone appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                recentsList
            }
        }
        .navigationTitle(Text("Recent Pages"))
    }

    private var recentsList: some View {
        List {
            if !receiver.preferences.keepHistory {
                Section {
                    Text("Recent pages are turned off in Settings.")
                    OpenSettingsButton(title: "Open Settings")
                }
            } else {
                ForEach(receiver.recents) { beam in
                    Button {
                        receiver.reopen(beam)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(beam.title ?? beam.url.host() ?? beam.url.absoluteString)
                                .font(.headline)
                            Text("\(beam.url.host() ?? ""), from \(beam.sender.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
