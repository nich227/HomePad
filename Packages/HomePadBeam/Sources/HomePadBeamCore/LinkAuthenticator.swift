import Foundation
import HomePadCore

public enum HelloRejection: Error, Equatable, Sendable {
    case wrongRole
    case unknownDevice
    case invalidProof
    case wrongHub
}

public enum HubAdmission: Equatable, Sendable {
    case known(PairedDevice)
    /// The device used the open invitation. The record must be saved and the invitation closed.
    case newlyPaired(PairedDevice)

    public var record: PairedDevice {
        switch self {
        case .known(let record), .newlyPaired(let record): record
        }
    }
}

/// Decides, on the hub, whether a hello belongs to a paired device or completes a pairing.
public enum HubAuthenticator {
    public static func admit(
        hello: LinkHello,
        hubID: UUID,
        paired: [PairedDevice],
        invitation: PendingInvitation?,
        now: Date
    ) -> Result<HubAdmission, HelloRejection> {
        let claimed = hello.device
        guard claimed.role == .companion else { return .failure(.wrongRole) }
        let name = BeamText.sanitizedDeviceName(claimed.name, fallback: BeamSettings.companionName.defaultValue)

        let existing = paired.first { $0.id == claimed.id }
        if let existing, existing.keys.isValidProof(hello.proof, deviceID: claimed.id, role: .companion) {
            var record = existing
            record.device.name = name
            return .success(.known(record))
        }
        if let invitation, !invitation.invitation.isExpired(at: now),
           invitation.invitation.keys.isValidProof(hello.proof, deviceID: claimed.id, role: .companion) {
            // The profile comes from the choice made on the hub, never from the device's claim.
            let device = PeerDevice(id: claimed.id, name: name, role: .companion, profileID: invitation.profileID)
            return .success(.newlyPaired(PairedDevice(device: device, secret: invitation.invitation.secret, hubID: hubID, pairedAt: now)))
        }
        return .failure(existing == nil ? .unknownDevice : .invalidProof)
    }

    /// The hub's own hello, answering a companion that was admitted with `keys`.
    public static func hello(hub: PeerDevice, keys: LinkKeys) -> LinkHello {
        LinkHello(device: hub, proof: keys.proof(deviceID: hub.id, role: .hub))
    }
}

/// The companion's side of the hello exchange.
public enum CompanionAuthenticator {
    public static func hello(companion: PeerDevice, keys: LinkKeys) -> LinkHello {
        LinkHello(device: companion, proof: keys.proof(deviceID: companion.id, role: .companion))
    }

    /// Checks the hub's answer against the pairing the companion used for this connection.
    public static func verify(hubHello: LinkHello, expectedHubID: UUID, keys: LinkKeys) -> Result<PeerDevice, HelloRejection> {
        let hub = hubHello.device
        guard hub.role == .hub else { return .failure(.wrongRole) }
        guard hub.id == expectedHubID else { return .failure(.wrongHub) }
        guard keys.isValidProof(hubHello.proof, deviceID: hub.id, role: .hub) else { return .failure(.invalidProof) }
        let name = BeamText.sanitizedDeviceName(hub.name, fallback: BeamSettings.hubName.defaultValue)
        return .success(PeerDevice(id: hub.id, name: name, role: .hub))
    }
}
