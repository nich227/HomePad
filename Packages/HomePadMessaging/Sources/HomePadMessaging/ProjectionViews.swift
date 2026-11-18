import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadMessagingCore
import SwiftUI
import UIKit

/// Text styles for projected content. Far away, every level steps up so the hub reads from across
/// a room. All levels are Dynamic Type styles.
struct ProjectionType {
    let title: Font
    let body: Font
    let detail: Font
    let rowSpacing: CGFloat
    let symbolSize: CGFloat

    init(_ proximity: Proximity) {
        switch proximity {
        case .far:
            title = .largeTitle.weight(.bold)
            body = .title.weight(.medium)
            detail = .title2
            rowSpacing = 22
            symbolSize = 44
        case .mid, .near:
            title = .title2.weight(.bold)
            body = .body
            detail = .subheadline
            rowSpacing = 12
            symbolSize = 26
        }
    }
}

extension RainbowTint {
    var color: Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: Empty and redacted states

/// Shown when no companion is projecting anything.
public struct ProjectionEmptyStateView: View {
    private let proximity: Proximity

    public init(proximity: Proximity = .near) {
        self.proximity = proximity
    }

    public var body: some View {
        let type = ProjectionType(proximity)
        VStack(spacing: type.rowSpacing) {
            HomePadAnimationView(.presencePulse)
                .frame(width: 160, height: 160)
            Text("Open HomePad on your iPhone nearby")
                .font(type.title)
                .multilineTextAlignment(.center)
            Text("Apps from your iPhone appear here while it is close and HomePad is open on it.")
                .font(type.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Stands in for personal content that exists but may not be shown to this viewer.
public struct RedactedPlaceholderView: View {
    private let app: ProjectedApp
    private let reason: VisibilityReason
    private let proximity: Proximity

    public init(app: ProjectedApp, reason: VisibilityReason, proximity: Proximity = .near) {
        self.app = app
        self.reason = reason
        self.proximity = proximity
    }

    public var body: some View {
        let type = ProjectionType(proximity)
        VStack(spacing: type.rowSpacing) {
            Image(systemName: "lock.fill")
                .font(.system(size: type.symbolSize * 1.6))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(app.name)
                .font(type.title)
            Text(explanation)
                .font(type.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var explanation: LocalizedStringKey {
        switch reason {
        case .ownerNotVerified:
            "Look at HomePad so it can recognize you. Personal content stays hidden until it does."
        case .sharedContent, .ownerVerified, .noOwner, .someoneElsePresent, .nobodyRecognized:
            "This content is personal and is hidden right now."
        }
    }
}

// MARK: App grid

/// The projected apps the current viewer may see. Redacted apps are greyed out with a lock.
public struct ProjectionAppGridView: View {
    private let client: ProjectionClient
    private let onOpen: (ProjectedAppEntry) -> Void

    public init(client: ProjectionClient, onOpen: @escaping (ProjectedAppEntry) -> Void) {
        self.client = client
        self.onOpen = onOpen
    }

    public var body: some View {
        let type = ProjectionType(client.proximity)
        let entries = client.entries
        if entries.isEmpty {
            ProjectionEmptyStateView(proximity: client.proximity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: client.proximity == .far ? 220 : 140), spacing: 24)], spacing: 24) {
                    ForEach(entries) { entry in
                        Button {
                            client.launch(entry.id)
                            onOpen(entry)
                        } label: {
                            ProjectedAppIcon(entry: entry, type: type)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: entry))
                        .accessibilityHint(entry.isRedacted ? Text("Personal content is locked.") : Text("Opens the app from \(entry.deviceName)."))
                    }
                }
                .padding(24)
            }
        }
    }

    private func accessibilityLabel(for entry: ProjectedAppEntry) -> Text {
        entry.isRedacted ? Text("\(entry.app.name), locked") : Text(entry.app.name)
    }
}

private struct ProjectedAppIcon: View {
    let entry: ProjectedAppEntry
    let type: ProjectionType

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: type.symbolSize * 0.6, style: .continuous)
                    .fill(entry.isRedacted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(entry.app.tint.color.gradient))
                    .frame(width: type.symbolSize * 2.6, height: type.symbolSize * 2.6)
                    .overlay {
                        Image(systemName: entry.app.symbolName)
                            .font(.system(size: type.symbolSize * 1.2, weight: .semibold))
                            .foregroundStyle(entry.isRedacted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                    }
                if entry.isRedacted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: type.symbolSize * 0.5))
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
            }
            Text(entry.app.name)
                .font(type.detail.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: One app

/// One projected app: its current screen, a back button when the companion pushed a screen, and
/// the redacted or loading state when there is nothing to show.
public struct ProjectionAppView: View {
    private let client: ProjectionClient
    private let entryID: ProjectedAppEntryID

    public init(client: ProjectionClient, entryID: ProjectedAppEntryID) {
        self.client = client
        self.entryID = entryID
    }

    public var body: some View {
        let type = ProjectionType(client.proximity)
        Group {
            switch client.content(for: entryID) {
            case .template(let template, let receivedAt, let depth):
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        if depth > 1 {
                            Button {
                                client.back(in: entryID)
                            } label: {
                                Label("Back", systemImage: "chevron.backward")
                                    .font(type.body)
                            }
                            .accessibilityLabel("Back")
                        }
                        Text(template.title)
                            .font(type.title)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                    }
                    .padding([.horizontal, .top], 24)
                    ProjectionTemplateView(
                        template: template,
                        receivedAt: receivedAt,
                        proximity: client.proximity,
                        onAction: { actionID, payload in client.perform(actionID: actionID, payload: payload, in: entryID) },
                        onMediaCommand: { client.send($0, in: entryID) }
                    )
                }
            case .redacted(let reason):
                if let entry = client.entry(entryID) {
                    RedactedPlaceholderView(app: entry.app, reason: reason, proximity: client.proximity)
                } else {
                    ProjectionEmptyStateView(proximity: client.proximity)
                }
            case .loading:
                ProgressView("Waiting for your iPhone")
                    .font(type.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ProjectionEmptyStateView(proximity: client.proximity)
            }
        }
    }
}

// MARK: Templates

/// Renders any valid template. It knows the template cases, not the apps.
public struct ProjectionTemplateView: View {
    private let template: ProjectionTemplate
    private let receivedAt: Date
    private let proximity: Proximity
    private let onAction: (String, [String: String]) -> Void
    private let onMediaCommand: (MediaCommand) -> Void

    public init(
        template: ProjectionTemplate,
        receivedAt: Date = Date(),
        proximity: Proximity = .near,
        onAction: @escaping (String, [String: String]) -> Void = { _, _ in },
        onMediaCommand: @escaping (MediaCommand) -> Void = { _ in }
    ) {
        self.template = template
        self.receivedAt = receivedAt
        self.proximity = proximity
        self.onAction = onAction
        self.onMediaCommand = onMediaCommand
    }

    private var type: ProjectionType { ProjectionType(proximity) }

    public var body: some View {
        switch template {
        case .list(let list): listView(list)
        case .grid(let grid): gridView(grid)
        case .nowPlaying(let nowPlaying): NowPlayingTemplateView(template: nowPlaying, receivedAt: receivedAt, type: type, onCommand: onMediaCommand)
        case .information(let information): informationView(information)
        case .agenda(let agenda): agendaView(agenda)
        }
    }

    // MARK: List

    @ViewBuilder
    private func listView(_ list: ListTemplate) -> some View {
        if list.sections.allSatisfy(\.rows.isEmpty) {
            emptyMessage(list.emptyMessage)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: type.rowSpacing) {
                    ForEach(list.sections) { section in
                        if let header = section.header {
                            Text(header)
                                .font(type.detail.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: ProjectionRow) -> some View {
        let label = HStack(spacing: 16) {
            if let symbolName = row.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: type.symbolSize))
                    .frame(width: type.symbolSize * 1.4)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(type.body)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(type.detail).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessoryView(row.accessory)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        if let actionID = row.actionID {
            Button {
                onAction(actionID, [:])
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func accessoryView(_ accessory: ProjectionRowAccessory) -> some View {
        switch accessory {
        case .none:
            EmptyView()
        case .disclosure:
            Image(systemName: "chevron.forward").font(type.detail).foregroundStyle(.tertiary).accessibilityHidden(true)
        case .toggle(let isOn):
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: type.symbolSize))
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityLabel(isOn ? Text("On") : Text("Off"))
        case .badge(let count):
            Text(count, format: .number)
                .font(type.detail.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        case .detail(let text):
            Text(text).font(type.detail).foregroundStyle(.secondary)
        }
    }

    // MARK: Grid

    private func gridView(_ grid: GridTemplate) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: proximity == .far ? 240 : 150), spacing: 20)], spacing: 20) {
                ForEach(grid.buttons) { button in
                    Button {
                        onAction(button.actionID, [:])
                    } label: {
                        VStack(spacing: 12) {
                            if let symbolName = button.symbolName {
                                Image(systemName: symbolName).font(.system(size: type.symbolSize * 1.4)).accessibilityHidden(true)
                            }
                            Text(button.title).font(type.body).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: type.symbolSize * 4)
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(button.title)
                }
            }
            .padding(24)
        }
    }

    // MARK: Information

    private func informationView(_ information: InformationTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: type.rowSpacing) {
                ForEach(information.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label).font(type.detail).foregroundStyle(.secondary)
                        Text(item.value).font(type.body)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !information.buttons.isEmpty {
                    HStack(spacing: 16) {
                        ForEach(information.buttons) { button in
                            Button {
                                onAction(button.actionID, [:])
                            } label: {
                                Label(button.title, systemImage: button.symbolName ?? "arrow.forward.circle")
                                    .font(type.body)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(button.title)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agendaView(_ agenda: AgendaTemplate) -> some View {
        if agenda.entries.isEmpty {
            emptyMessage(agenda.emptyMessage)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: type.rowSpacing) {
                    ForEach(agenda.entries) { entry in
                        agendaRow(entry)
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func agendaRow(_ entry: AgendaEntry) -> some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: symbol(for: entry))
                .font(.system(size: type.symbolSize))
                .foregroundStyle(entry.isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: type.symbolSize * 1.4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(type.body)
                    .strikethrough(entry.isCompleted)
                if let when = whenText(for: entry) {
                    Text(when).font(type.detail).foregroundStyle(.secondary)
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail).font(type.detail).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        if let actionID = entry.actionID {
            Button {
                onAction(actionID, [:])
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(entry.isCompleted ? Text("Completed") : Text("Not completed"))
            .accessibilityHint("Marks the reminder as done or not done on the iPhone.")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    private func symbol(for entry: AgendaEntry) -> String {
        switch entry.kind {
        case .event: "calendar"
        case .reminder: entry.isCompleted ? "checkmark.circle.fill" : "circle"
        }
    }

    private func whenText(for entry: AgendaEntry) -> String? {
        guard let start = entry.start else { return nil }
        if entry.isAllDay {
            return start.formatted(.dateTime.weekday(.wide).month().day())
        }
        if entry.kind == .event, let end = entry.end, end > start {
            return (start..<end).formatted(.interval.weekday(.abbreviated).hour().minute())
        }
        return start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func emptyMessage(_ message: String?) -> some View {
        Text(message ?? String(localized: "Nothing to show."))
            .font(type.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NowPlayingTemplateView: View {
    let template: NowPlayingTemplate
    let receivedAt: Date
    let type: ProjectionType
    let onCommand: (MediaCommand) -> Void

    var body: some View {
        VStack(spacing: type.rowSpacing) {
            artwork
            VStack(spacing: 6) {
                Text(template.title).font(type.title).multilineTextAlignment(.center)
                if let artist = template.artist {
                    Text(artist).font(type.body).foregroundStyle(.secondary)
                }
                if let album = template.album {
                    Text(album).font(type.detail).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if template.duration > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = NowPlayingProjection.elapsed(for: template, receivedAt: receivedAt, now: context.date)
                    ProgressView(value: elapsed, total: template.duration)
                        .accessibilityLabel("Playback position")
                        .accessibilityValue(Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond))))
                }
                .frame(maxWidth: 520)
            }
            HStack(spacing: type.symbolSize) {
                ForEach(orderedCommands, id: \.self) { command in
                    Button {
                        onCommand(command)
                    } label: {
                        Image(systemName: symbol(for: command))
                            .font(.system(size: type.symbolSize * 1.3))
                            .frame(minWidth: 60, minHeight: 60)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(for: command))
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = template.artwork, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.quaternary)
                .frame(width: 220, height: 220)
                .overlay { Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.secondary) }
                .accessibilityHidden(true)
        }
    }

    private var orderedCommands: [MediaCommand] {
        let order: [MediaCommand] = [.restartTrack, .previousTrack, .play, .pause, .nextTrack]
        return order.filter(template.commands.contains)
    }

    private func symbol(for command: MediaCommand) -> String {
        switch command {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .nextTrack: "forward.fill"
        case .previousTrack: "backward.fill"
        case .restartTrack: "backward.end.fill"
        }
    }

    private func label(for command: MediaCommand) -> Text {
        switch command {
        case .play: Text("Play")
        case .pause: Text("Pause")
        case .nextTrack: Text("Next Track")
        case .previousTrack: Text("Previous Track")
        case .restartTrack: Text("Restart Track")
        }
    }
}
