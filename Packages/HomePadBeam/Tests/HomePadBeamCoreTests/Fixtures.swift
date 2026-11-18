import Foundation
import HomePadCore
@testable import HomePadBeamCore

struct FixedRandom: RandomSource {
    var fill: UInt8 = 7
    var shortBy = 0
    func bytes(_ count: Int) -> Data { Data(repeating: fill, count: count - shortBy) }
}

enum Fixture {
    static let hubID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID()
    static let phoneID = UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()
    static let otherPhoneID = UUID(uuidString: "99999999-2222-3333-4444-555555555555") ?? UUID()
    static let profileID = UUID(uuidString: "ABABABAB-0000-0000-0000-000000000001") ?? UUID()
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func secret(_ fill: UInt8 = 1) -> PairingSecret {
        secret(bytes: Data(repeating: fill, count: PairingSecret.byteCount))
    }

    static func secret(bytes: Data) -> PairingSecret {
        do {
            return try PairingSecret(bytes: bytes)
        } catch {
            preconditionFailure("fixture secrets must be 32 bytes")
        }
    }

    static let sequentialSecret = secret(bytes: Data(0..<32))

    static let hub = PeerDevice(id: hubID, name: "Kitchen", role: .hub)
    static let phone = PeerDevice(id: phoneID, name: "Ada's iPhone", role: .companion)
    static let otherPhone = PeerDevice(id: otherPhoneID, name: "Bo's iPhone", role: .companion)

    static func paired(_ device: PeerDevice = phone, fill: UInt8 = 1, approved: Int = 0) -> PairedDevice {
        PairedDevice(device: device, secret: secret(fill), hubID: hubID, pairedAt: now, approvedBeamCount: approved)
    }

    static func invitation(fill: UInt8 = 9, expiresIn: TimeInterval = 120, profileID: UUID? = profileID) -> PendingInvitation {
        PendingInvitation(
            invitation: PairingInvitation(hubID: hubID, hubName: "Kitchen", secret: secret(fill), expiresAt: now.addingTimeInterval(expiresIn)),
            profileID: profileID
        )
    }

    static func beam(_ url: String = "https://example.com/recipe?id=1", id: UUID = UUID(), sender: PeerDevice = phone, title: String? = "Soup") -> BeamPayload {
        BeamPayload(id: id, url: URL(string: url) ?? URL(fileURLWithPath: "/"), title: title, sender: sender, sentAt: now)
    }

    static func validated(_ text: String, policy: BeamURLPolicy = BeamURLPolicy()) -> ValidatedURL? {
        try? policy.validate(text).get()
    }
}
