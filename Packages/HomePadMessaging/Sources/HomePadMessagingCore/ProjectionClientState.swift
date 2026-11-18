import Foundation
import HomePadCore

public enum ProjectionStateError: Error, Equatable, Sendable {
    /// Only companions project to hubs, and only hubs send commands to companions.
    case senderRoleNotAllowed
    /// A frame arrived before the sender announced its apps in this session.
    case notAnnounced
    /// The sequence number did not increase: a duplicate or a replay.
    case staleSequence
    case unknownApp(String)
    case unknownTemplate(String)
    case noRoot(String)
    case cannotPopRoot(String)
    case invalid(ProjectionValidationError)
}

public struct ProjectedAppEntryID: Hashable, Sendable {
    public let deviceID: UUID
    public let appID: String

    public init(deviceID: UUID, appID: String) {
        self.deviceID = deviceID
        self.appID = appID
    }
}

/// One projected app as the hub lists it for the person in front of it.
public struct ProjectedAppEntry: Identifiable, Sendable, Equatable {
    public let id: ProjectedAppEntryID
    public let app: ProjectedApp
    public let deviceName: String
    public let ownerProfileID: UUID?
    public let decision: VisibilityDecision

    public var isRedacted: Bool { decision.visibility == .redacted }
}

public enum ProjectedContent: Sendable, Equatable {
    /// `receivedAt` is on the hub's clock. `depth` is 1 for the root.
    case template(ProjectionTemplate, receivedAt: Date, depth: Int)
    /// The app is listed but its content is withheld.
    case redacted(VisibilityReason)
    /// Visible, but the companion has not sent a root template yet.
    case loading
    /// Hidden from this viewer, withdrawn, or the companion disconnected.
    case unavailable
}

public struct ProjectionPresentationRequest: Sendable, Equatable {
    public let entryID: ProjectedAppEntryID
    public let requestedAt: Date
}

/// Hub-side projection state: which companions project which apps, and each app's navigation
/// stack. Templates are held memory-only and are dropped when their companion disconnects.
public struct ProjectionClientState: Sendable, Equatable {
    struct StackEntry: Sendable, Equatable {
        var template: ProjectionTemplate
        var receivedAt: Date
    }

    struct DeviceProjection: Sendable, Equatable {
        var device: PeerDevice
        var session: UUID
        var lastSequence: UInt64
        var apps: [ProjectedApp]
        var stacks: MemoryOnly<[String: [StackEntry]]>
    }

    public let session: UUID
    public let limits: ProjectionLimits
    /// How long to wait before asking an unannounced companion again.
    public let helloRetryInterval: TimeInterval
    public private(set) var presentationRequest: ProjectionPresentationRequest?
    private var devices: [UUID: DeviceProjection] = [:]
    private var helloSentAt: [UUID: Date] = [:]
    private var outgoingSequence: UInt64 = 0

    public init(session: UUID, limits: ProjectionLimits = .standard, helloRetryInterval: TimeInterval = 10) {
        self.session = session
        self.limits = limits
        self.helloRetryInterval = helloRetryInterval
    }

    private var validator: ProjectionValidator { ProjectionValidator(limits: limits) }

    // MARK: Incoming

    public mutating func apply(
        _ frame: ProjectionFrame<HostToHubMessage>,
        from device: PeerDevice,
        now: Date
    ) throws(ProjectionStateError) {
        guard device.role == .companion else { throw .senderRoleNotAllowed }
        switch frame.message {
        case .announce(let apps):
            try announce(apps, frame: frame, device: device)
        case .setRoot(let appID, let template):
            var projection = try accept(frame, from: device, appID: appID)
            try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
            projection.stacks.mutate { $0[appID] = [StackEntry(template: template, receivedAt: now)] }
            devices[device.id] = projection
        case .push(let appID, let template):
            var projection = try accept(frame, from: device, appID: appID)
            try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
            let stack = projection.stacks.reveal()[appID] ?? []
            guard !stack.isEmpty else { throw .noRoot(appID) }
            guard stack.count < limits.maxNavigationDepth else {
                throw .invalid(.navigationDepthExceeded(limit: limits.maxNavigationDepth))
            }
            guard !stack.contains(where: { $0.template.id == template.id }) else {
                throw .invalid(.duplicateIdentifier(field: "template.id"))
            }
            projection.stacks.mutate { $0[appID]?.append(StackEntry(template: template, receivedAt: now)) }
            devices[device.id] = projection
        case .pop(let appID):
            var projection = try accept(frame, from: device, appID: appID)
            guard (projection.stacks.reveal()[appID]?.count ?? 0) > 1 else { throw .cannotPopRoot(appID) }
            projection.stacks.mutate { _ = $0[appID]?.popLast() }
            devices[device.id] = projection
        case .update(let appID, let template):
            var projection = try accept(frame, from: device, appID: appID)
            try checked { () throws(ProjectionValidationError) in try validator.validate(template) }
            guard let index = projection.stacks.reveal()[appID]?.firstIndex(where: { $0.template.id == template.id }) else {
                throw .unknownTemplate(template.id)
            }
            projection.stacks.mutate { $0[appID]?[index] = StackEntry(template: template, receivedAt: now) }
            devices[device.id] = projection
        case .withdraw(let appID):
            var projection = try accept(frame, from: device, appID: appID)
            projection.apps.removeAll { $0.id == appID }
            projection.stacks.mutate { $0[appID] = nil }
            devices[device.id] = projection
            if presentationRequest?.entryID == ProjectedAppEntryID(deviceID: device.id, appID: appID) {
                presentationRequest = nil
            }
        case .present(let appID):
            _ = try accept(frame, from: device, appID: appID)
            presentationRequest = ProjectionPresentationRequest(
                entryID: ProjectedAppEntryID(deviceID: device.id, appID: appID),
                requestedAt: now
            )
        }
    }

    private mutating func announce(
        _ apps: [ProjectedApp],
        frame: ProjectionFrame<HostToHubMessage>,
        device: PeerDevice
    ) throws(ProjectionStateError) {
        // A new session means the companion restarted, so nothing it showed before is current.
        var previous: [String: [StackEntry]] = [:]
        if let existing = devices[device.id], existing.session == frame.session {
            guard frame.sequence > existing.lastSequence else { throw .staleSequence }
            previous = existing.stacks.reveal()
        }
        try checked { () throws(ProjectionValidationError) in try validator.validate(apps: apps) }
        let announced = Set(apps.map(\.id))
        devices[device.id] = DeviceProjection(
            device: device,
            session: frame.session,
            lastSequence: frame.sequence,
            apps: apps,
            stacks: MemoryOnly(previous.filter { announced.contains($0.key) })
        )
        if let request = presentationRequest, request.entryID.deviceID == device.id, !announced.contains(request.entryID.appID) {
            presentationRequest = nil
        }
    }

    /// Checks session, order, and that the app was announced. The sequence number is consumed
    /// even when the rest of the frame is later rejected, so a rejected frame cannot be replayed.
    private mutating func accept(
        _ frame: ProjectionFrame<HostToHubMessage>,
        from device: PeerDevice,
        appID: String
    ) throws(ProjectionStateError) -> DeviceProjection {
        guard var projection = devices[device.id], projection.session == frame.session else { throw .notAnnounced }
        guard frame.sequence > projection.lastSequence else { throw .staleSequence }
        projection.lastSequence = frame.sequence
        projection.device = device
        devices[device.id] = projection
        guard projection.apps.contains(where: { $0.id == appID }) else { throw .unknownApp(appID) }
        return projection
    }

    private func checked(_ body: () throws(ProjectionValidationError) -> Void) throws(ProjectionStateError) {
        do {
            try body()
        } catch {
            throw .invalid(error)
        }
    }

    // MARK: Connections

    /// Drops everything a companion projected. Call as soon as its link goes away.
    public mutating func deviceDisconnected(_ deviceID: UUID) {
        devices[deviceID] = nil
        helloSentAt[deviceID] = nil
        if presentationRequest?.entryID.deviceID == deviceID {
            presentationRequest = nil
        }
    }

    /// Brings the state in line with the peers that are connected right now. Returns the
    /// companions that should be sent `hello` because they have not announced anything.
    public mutating func reconcile(connected: [PeerDevice], now: Date) -> [UUID] {
        let companions = connected.filter { $0.role == .companion }
        let connectedIDs = Set(companions.map(\.id))
        for deviceID in Set(devices.keys).union(helloSentAt.keys) where !connectedIDs.contains(deviceID) {
            deviceDisconnected(deviceID)
        }
        var toGreet: [UUID] = []
        for companion in companions {
            if devices[companion.id] != nil {
                // A companion can be reassigned to another member while connected.
                devices[companion.id]?.device = companion
                continue
            }
            if let sentAt = helloSentAt[companion.id], now.timeIntervalSince(sentAt) < helloRetryInterval {
                continue
            }
            helloSentAt[companion.id] = now
            toGreet.append(companion.id)
        }
        return toGreet
    }

    public var connectedDeviceIDs: Set<UUID> { Set(devices.keys) }

    public mutating func clearPresentationRequest() {
        presentationRequest = nil
    }

    // MARK: Outgoing

    public mutating func frame(for message: HubToHostMessage) -> ProjectionFrame<HubToHostMessage> {
        outgoingSequence += 1
        return ProjectionFrame(session: session, sequence: outgoingSequence, message: message)
    }

    // MARK: Queries

    /// Apps the viewer may know about, hidden ones left out, ordered by device name then by the
    /// order the companion announced them.
    public func entries(viewer: ViewerContext) -> [ProjectedAppEntry] {
        devices.values
            .sorted { ($0.device.name, $0.device.id.uuidString) < ($1.device.name, $1.device.id.uuidString) }
            .flatMap { projection in
                projection.apps.compactMap { app -> ProjectedAppEntry? in
                    let decision = ProjectionVisibilityPolicy.decide(
                        ownerProfileID: projection.device.profileID,
                        requiresPersonalContent: app.requiresPersonalContent,
                        viewer: viewer
                    )
                    guard decision.visibility != .hidden else { return nil }
                    return ProjectedAppEntry(
                        id: ProjectedAppEntryID(deviceID: projection.device.id, appID: app.id),
                        app: app,
                        deviceName: projection.device.name,
                        ownerProfileID: projection.device.profileID,
                        decision: decision
                    )
                }
            }
    }

    public func entry(_ id: ProjectedAppEntryID, viewer: ViewerContext) -> ProjectedAppEntry? {
        entries(viewer: viewer).first { $0.id == id }
    }

    /// The template at `depth` (1 is the root, `nil` is the top of the stack), after the
    /// visibility policy has been applied for this viewer.
    public func content(for id: ProjectedAppEntryID, depth: Int? = nil, viewer: ViewerContext) -> ProjectedContent {
        // `entry` leaves hidden apps out, so what remains is either visible or redacted.
        guard let entry = entry(id, viewer: viewer) else { return .unavailable }
        guard entry.decision.visibility == .visible else { return .redacted(entry.decision.reason) }
        let stack = devices[id.deviceID]?.stacks.reveal()[id.appID] ?? []
        let index = (depth ?? stack.count) - 1
        guard stack.indices.contains(index) else { return .loading }
        return .template(stack[index].template, receivedAt: stack[index].receivedAt, depth: index + 1)
    }

    public func navigationDepth(for id: ProjectedAppEntryID) -> Int {
        devices[id.deviceID]?.stacks.reveal()[id.appID]?.count ?? 0
    }
}
