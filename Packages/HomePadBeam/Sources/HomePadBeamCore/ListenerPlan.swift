import Foundation

/// What a hub publishes over Bonjour: a random ID and the name chosen in Settings. Nothing that
/// identifies a person or a device model.
public struct HubAdvertisement: Equatable, Sendable {
    public static let idKey = "id"
    public static let versionKey = "v"
    public static let version = "1"

    public let hubID: UUID
    public let name: String

    public init(hubID: UUID, name: String) {
        self.hubID = hubID
        self.name = BeamText.sanitizedDeviceName(name, fallback: BeamSettings.hubName.defaultValue)
    }

    public var txtRecord: [String: String] {
        [Self.idKey: hubID.uuidString, Self.versionKey: Self.version]
    }

    /// Reads another hub's advertisement. The result is only a hint for choosing which pairing
    /// to try; the TLS handshake is what proves the hub is the paired one.
    public static func parse(serviceName: String, txtRecord: [String: String]) -> HubAdvertisement? {
        guard txtRecord[versionKey] == version, let id = txtRecord[idKey].flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        return HubAdvertisement(hubID: id, name: serviceName)
    }
}

/// Whether the hub should listen, and with which keys. `nil` means no socket is open.
public struct ListenerPlan: Equatable, Sendable {
    public let credentials: [LinkCredential]
    public let advertisement: HubAdvertisement

    /// - Parameters:
    ///   - sceneActive: The hub's scene is in the foreground.
    ///   - receiveEnabled: The "Receive Beams" preference.
    ///   - invitation: The pairing invitation on screen, if any.
    public static func make(
        sceneActive: Bool,
        receiveEnabled: Bool,
        hubID: UUID,
        hubName: String,
        paired: [PairedDevice],
        invitation: PendingInvitation?,
        now: Date
    ) -> ListenerPlan? {
        guard sceneActive else { return nil }
        var credentials: [LinkCredential] = []
        if receiveEnabled {
            credentials = paired.map(\.keys.credential)
        }
        if let invitation, !invitation.invitation.isExpired(at: now) {
            credentials.append(invitation.invitation.keys.credential)
        }
        var seen = Set<Data>()
        credentials = credentials.filter { seen.insert($0.identity).inserted }
        guard !credentials.isEmpty else { return nil }
        return ListenerPlan(credentials: credentials, advertisement: HubAdvertisement(hubID: hubID, name: hubName))
    }
}
