import Foundation

public enum ProjectionProtocol {
    public static let currentVersion = 1
    public static let supportedVersions: ClosedRange<Int> = 1...1
}

/// Companion (host) to hub.
public enum HostToHubMessage: Sendable, Equatable {
    /// The full list of apps this companion projects. Starts or refreshes a session.
    case announce([ProjectedApp])
    case setRoot(appID: String, template: ProjectionTemplate)
    case push(appID: String, template: ProjectionTemplate)
    case pop(appID: String)
    /// Replaces the template with the same id wherever it is in the app's stack.
    case update(appID: String, template: ProjectionTemplate)
    case withdraw(appID: String)
    /// Asks the hub to bring an app to the front.
    case present(appID: String)
}

/// Hub to companion (host).
public enum HubToHostMessage: Sendable, Equatable {
    /// Asks the companion to announce its apps and resend its templates.
    case hello
    case launch(appID: String)
    case action(appID: String, actionID: String, payload: [String: String])
    case mediaCommand(MediaCommand)
}

/// Action ids the hub itself sends, as opposed to ids that came from a template.
public enum ProjectionReservedAction {
    /// The hub's back button. The companion owns the navigation stack and answers with `pop`.
    public static let back = "homepad.back"
}

public struct ProjectionFrame<Message: Sendable & Equatable>: Sendable, Equatable {
    public let version: Int
    /// Changes every time the sender's process starts, so a receiver can tell a restart from a replay.
    public let session: UUID
    /// Strictly increasing within a session.
    public let sequence: UInt64
    public let message: Message

    public init(version: Int = ProjectionProtocol.currentVersion, session: UUID, sequence: UInt64, message: Message) {
        self.version = version
        self.session = session
        self.sequence = sequence
        self.message = message
    }
}

public enum ProjectionWireError: Error, Equatable, Sendable {
    case payloadTooLarge(limit: Int)
    case malformed
    case unsupportedVersion(Int)
    case unknownMessageType
    case invalid(ProjectionValidationError)
}

/// JSON codec for projection frames. Decoding fails closed: an unknown version, an unknown message
/// type, an unknown template case, a missing field, or content outside the limits rejects the
/// whole frame.
public struct ProjectionCodec: Sendable {
    public let limits: ProjectionLimits
    private let validator: ProjectionValidator

    public init(limits: ProjectionLimits = .standard) {
        self.limits = limits
        self.validator = ProjectionValidator(limits: limits)
    }

    // MARK: Host to hub

    public func encode(_ frame: ProjectionFrame<HostToHubMessage>) throws(ProjectionWireError) -> Data {
        var wire = WireFrame(frame: frame, type: "")
        switch frame.message {
        case .announce(let apps):
            wire.type = HostType.announce.rawValue
            wire.apps = apps
        case .setRoot(let appID, let template):
            wire.type = HostType.setRoot.rawValue
            wire.appID = appID
            wire.template = template
        case .push(let appID, let template):
            wire.type = HostType.push.rawValue
            wire.appID = appID
            wire.template = template
        case .pop(let appID):
            wire.type = HostType.pop.rawValue
            wire.appID = appID
        case .update(let appID, let template):
            wire.type = HostType.update.rawValue
            wire.appID = appID
            wire.template = template
        case .withdraw(let appID):
            wire.type = HostType.withdraw.rawValue
            wire.appID = appID
        case .present(let appID):
            wire.type = HostType.present.rawValue
            wire.appID = appID
        }
        try validate(frame.message)
        return try serialize(wire)
    }

    public func decodeHostFrame(_ data: Data) throws(ProjectionWireError) -> ProjectionFrame<HostToHubMessage> {
        let (wire, type): (WireFrame, HostType) = try parse(data)
        let message: HostToHubMessage
        switch type {
        case .announce:
            message = .announce(try required(wire.apps))
        case .setRoot:
            message = .setRoot(appID: try required(wire.appID), template: try required(wire.template))
        case .push:
            message = .push(appID: try required(wire.appID), template: try required(wire.template))
        case .pop:
            message = .pop(appID: try required(wire.appID))
        case .update:
            message = .update(appID: try required(wire.appID), template: try required(wire.template))
        case .withdraw:
            message = .withdraw(appID: try required(wire.appID))
        case .present:
            message = .present(appID: try required(wire.appID))
        }
        try validate(message)
        return ProjectionFrame(version: wire.version, session: wire.session, sequence: wire.sequence, message: message)
    }

    // MARK: Hub to host

    public func encode(_ frame: ProjectionFrame<HubToHostMessage>) throws(ProjectionWireError) -> Data {
        var wire = WireFrame(frame: frame, type: "")
        switch frame.message {
        case .hello:
            wire.type = HubType.hello.rawValue
        case .launch(let appID):
            wire.type = HubType.launch.rawValue
            wire.appID = appID
        case .action(let appID, let actionID, let payload):
            wire.type = HubType.action.rawValue
            wire.appID = appID
            wire.actionID = actionID
            wire.payload = payload
        case .mediaCommand(let command):
            wire.type = HubType.mediaCommand.rawValue
            wire.command = command
        }
        try validate(frame.message)
        return try serialize(wire)
    }

    public func decodeHubFrame(_ data: Data) throws(ProjectionWireError) -> ProjectionFrame<HubToHostMessage> {
        let (wire, type): (WireFrame, HubType) = try parse(data)
        let message: HubToHostMessage
        switch type {
        case .hello:
            message = .hello
        case .launch:
            message = .launch(appID: try required(wire.appID))
        case .action:
            message = .action(appID: try required(wire.appID), actionID: try required(wire.actionID), payload: wire.payload ?? [:])
        case .mediaCommand:
            message = .mediaCommand(try required(wire.command))
        }
        try validate(message)
        return ProjectionFrame(version: wire.version, session: wire.session, sequence: wire.sequence, message: message)
    }

    // MARK: Validation

    func validate(_ message: HostToHubMessage) throws(ProjectionWireError) {
        do {
            switch message {
            case .announce(let apps):
                try validator.validate(apps: apps)
            case .setRoot(let appID, let template), .push(let appID, let template), .update(let appID, let template):
                try validator.validate(appID: appID)
                try validator.validate(template)
            case .pop(let appID), .withdraw(let appID), .present(let appID):
                try validator.validate(appID: appID)
            }
        } catch {
            throw .invalid(error)
        }
    }

    func validate(_ message: HubToHostMessage) throws(ProjectionWireError) {
        do {
            switch message {
            case .hello, .mediaCommand:
                break
            case .launch(let appID):
                try validator.validate(appID: appID)
            case .action(let appID, let actionID, let payload):
                try validator.validate(appID: appID)
                try validator.validate(actionID: actionID, payload: payload)
            }
        } catch {
            throw .invalid(error)
        }
    }

    // MARK: Plumbing

    private func serialize(_ wire: WireFrame) throws(ProjectionWireError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(wire) else { throw .malformed }
        guard data.count <= limits.maxPayloadBytes else { throw .payloadTooLarge(limit: limits.maxPayloadBytes) }
        return data
    }

    private func parse<MessageType: RawRepresentable>(_ data: Data) throws(ProjectionWireError) -> (WireFrame, MessageType)
    where MessageType.RawValue == String {
        guard data.count <= limits.maxPayloadBytes else { throw .payloadTooLarge(limit: limits.maxPayloadBytes) }
        let decoder = JSONDecoder()
        // The header is read on its own so a newer version is reported as such even when the rest
        // of its frame has a shape this build cannot decode.
        guard let header = try? decoder.decode(WireHeader.self, from: data) else { throw .malformed }
        guard ProjectionProtocol.supportedVersions.contains(header.version) else {
            throw .unsupportedVersion(header.version)
        }
        guard let type = MessageType(rawValue: header.type) else { throw .unknownMessageType }
        guard let wire = try? decoder.decode(WireFrame.self, from: data) else { throw .malformed }
        return (wire, type)
    }

    private func required<Value>(_ value: Value?) throws(ProjectionWireError) -> Value {
        guard let value else { throw .malformed }
        return value
    }
}

private enum HostType: String {
    case announce, setRoot, push, pop, update, withdraw, present
}

private enum HubType: String {
    case hello, launch, action, mediaCommand
}

private struct WireHeader: Decodable {
    let version: Int
    let type: String
}

private struct WireFrame: Codable {
    var version: Int
    var session: UUID
    var sequence: UInt64
    var type: String
    var apps: [ProjectedApp]?
    var appID: String?
    var template: ProjectionTemplate?
    var actionID: String?
    var payload: [String: String]?
    var command: MediaCommand?

    init<Message>(frame: ProjectionFrame<Message>, type: String) {
        self.version = frame.version
        self.session = frame.session
        self.sequence = frame.sequence
        self.type = type
    }
}
