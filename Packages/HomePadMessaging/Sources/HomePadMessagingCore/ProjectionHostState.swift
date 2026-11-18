import Foundation
import HomePadCore

/// What the companion must do after a hub frame was accepted.
public enum ProjectionHostEvent: Sendable, Equatable {
    /// Send `snapshot()` to this hub: it is new, restarted, or asked for it.
    case sendSnapshot(hubID: UUID)
    case launch(appID: String, hubID: UUID)
    case action(appID: String, actionID: String, payload: [String: String], hubID: UUID)
    /// The hub's back button.
    case back(appID: String, hubID: UUID)
    case mediaCommand(MediaCommand, hubID: UUID)
}

/// Companion-side projection state: the registered apps, each app's navigation stack, and the
/// hubs being served. The companion owns navigation; hubs mirror it.
public struct ProjectionHostState: Sendable, Equatable {
    struct HubLink: Sendable, Equatable {
        var session: UUID
        var lastSequence: UInt64
        var lastHeardAt: Date
    }

    public let session: UUID
    public let limits: ProjectionLimits
    public private(set) var apps: [ProjectedApp] = []
    private var stacks: [String: [ProjectionTemplate]] = [:]
    private var links: [UUID: HubLink] = [:]
    private var knownHubs: Set<UUID> = []
    private var outgoingSequence: UInt64 = 0

    public init(session: UUID, limits: ProjectionLimits = .standard) {
        self.session = session
        self.limits = limits
    }

    private var validator: ProjectionValidator { ProjectionValidator(limits: limits) }

    // MARK: Apps and navigation

    /// Adds an app with its root template. Returns the messages to send to every hub.
    public mutating func register(_ app: ProjectedApp, root: ProjectionTemplate) throws(ProjectionStateError) -> [HostToHubMessage] {
        var updated = apps.filter { $0.id != app.id }
        updated.append(app)
        try checked { () throws(ProjectionValidationError) in
            try validator.validate(apps: updated)
            try validator.validate(root)
        }
        apps = updated
        stacks[app.id] = [root]
        return [.announce(apps), .setRoot(appID: app.id, template: root)]
    }

    public mutating func unregister(appID: String) throws(ProjectionStateError) -> [HostToHubMessage] {
        try requireApp(appID)
        apps.removeAll { $0.id == appID }
        stacks[appID] = nil
        return [.withdraw(appID: appID)]
    }

    public mutating func setRoot(appID: String, template: ProjectionTemplate) throws(ProjectionStateError) -> HostToHubMessage {
        try requireApp(appID)
        try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
        stacks[appID] = [template]
        return .setRoot(appID: appID, template: template)
    }

    public mutating func push(appID: String, template: ProjectionTemplate) throws(ProjectionStateError) -> HostToHubMessage {
        try requireApp(appID)
        try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
        let stack = stack(appID: appID)
        guard stack.count < limits.maxNavigationDepth else {
            throw .invalid(.navigationDepthExceeded(limit: limits.maxNavigationDepth))
        }
        guard !stack.contains(where: { $0.id == template.id }) else {
            throw .invalid(.duplicateIdentifier(field: "template.id"))
        }
        stacks[appID] = stack + [template]
        return .push(appID: appID, template: template)
    }

    public mutating func pop(appID: String) throws(ProjectionStateError) -> HostToHubMessage {
        try requireApp(appID)
        let stack = stack(appID: appID)
        guard stack.count > 1 else { throw .cannotPopRoot(appID) }
        stacks[appID] = Array(stack.dropLast())
        return .pop(appID: appID)
    }

    /// Replaces the template with the same id. Returns `nil` when nothing changed, so an
    /// unchanged template is not sent again.
    public mutating func update(appID: String, template: ProjectionTemplate) throws(ProjectionStateError) -> HostToHubMessage? {
        try requireApp(appID)
        guard let index = stacks[appID]?.firstIndex(where: { $0.id == template.id }) else {
            throw .unknownTemplate(template.id)
        }
        guard stacks[appID]?[index] != template else { return nil }
        try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
        stacks[appID]?[index] = template
        return .update(appID: appID, template: template)
    }

    public func stack(appID: String) -> [ProjectionTemplate] {
        stacks[appID] ?? []
    }

    /// Everything a hub needs to mirror the current state from nothing.
    public func snapshot() -> [HostToHubMessage] {
        var messages: [HostToHubMessage] = [.announce(apps)]
        for app in apps {
            for (index, template) in stack(appID: app.id).enumerated() {
                messages.append(index == 0 ? .setRoot(appID: app.id, template: template) : .push(appID: app.id, template: template))
            }
        }
        return messages
    }

    public mutating func frame(for message: HostToHubMessage) -> ProjectionFrame<HostToHubMessage> {
        outgoingSequence += 1
        return ProjectionFrame(session: session, sequence: outgoingSequence, message: message)
    }

    // MARK: Hubs

    public var hubIDs: Set<UUID> { knownHubs }

    /// Brings the hub list in line with the connected peers. Returns hubs that just appeared and
    /// need a snapshot.
    public mutating func reconcile(connected: [PeerDevice]) -> [UUID] {
        let hubs = connected.filter { $0.role == .hub }.map(\.id)
        let current = Set(hubs)
        for hubID in knownHubs.subtracting(current) {
            links[hubID] = nil
        }
        let added = hubs.filter { !knownHubs.contains($0) }
        knownHubs = current
        return added
    }

    public mutating func receive(
        _ frame: ProjectionFrame<HubToHostMessage>,
        from hub: PeerDevice,
        now: Date
    ) throws(ProjectionStateError) -> [ProjectionHostEvent] {
        guard hub.role == .hub else { throw .senderRoleNotAllowed }
        var events: [ProjectionHostEvent] = []
        if let link = links[hub.id], link.session == frame.session {
            guard frame.sequence > link.lastSequence else { throw .staleSequence }
        } else if frame.message != .hello {
            // A hub that restarted has lost its mirror of this companion.
            events.append(.sendSnapshot(hubID: hub.id))
        }
        links[hub.id] = HubLink(session: frame.session, lastSequence: frame.sequence, lastHeardAt: now)
        knownHubs.insert(hub.id)

        switch frame.message {
        case .hello:
            events.append(.sendSnapshot(hubID: hub.id))
        case .launch(let appID):
            try requireApp(appID)
            events.append(.launch(appID: appID, hubID: hub.id))
        case .action(let appID, let actionID, let payload):
            try requireApp(appID)
            try checked { () throws(ProjectionValidationError) in try validator.validate(actionID: actionID, payload: payload) }
            if actionID == ProjectionReservedAction.back {
                events.append(.back(appID: appID, hubID: hub.id))
            } else {
                events.append(.action(appID: appID, actionID: actionID, payload: payload, hubID: hub.id))
            }
        case .mediaCommand(let command):
            events.append(.mediaCommand(command, hubID: hub.id))
        }
        return events
    }

    public func lastHeard(from hubID: UUID) -> Date? {
        links[hubID]?.lastHeardAt
    }

    private func requireApp(_ appID: String) throws(ProjectionStateError) {
        guard apps.contains(where: { $0.id == appID }) else { throw .unknownApp(appID) }
    }

    private func checked(_ body: () throws(ProjectionValidationError) -> Void) throws(ProjectionStateError) {
        do {
            try body()
        } catch {
            throw .invalid(error)
        }
    }
}
