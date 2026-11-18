import CryptoKit
import Foundation
import HomePadCore

/// A TLS pre-shared key and the identity the client offers for it.
public struct LinkCredential: Equatable, Hashable, Sendable, CustomStringConvertible, CustomReflectable {
    public let identity: Data
    public let key: Data

    public init(identity: Data, key: Data) {
        self.identity = identity
        self.key = key
    }

    public var description: String { "LinkCredential(redacted)" }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Everything derived from one pairing secret. The hub ID salts the derivation so a secret is
/// only useful against the hub that issued it.
public struct LinkKeys: Equatable, Sendable, CustomStringConvertible, CustomReflectable {
    static let pskInfo = Data("HomePad Beam v1 tls psk".utf8)
    static let identityInfo = Data("HomePad Beam v1 tls psk identity".utf8)
    static let helloInfo = Data("HomePad Beam v1 hello auth".utf8)
    static let proofLabel = Data("HomePad Beam v1 hello".utf8)

    public let credential: LinkCredential
    private let helloKey: Data

    public static func derive(secret: PairingSecret, hubID: UUID) -> LinkKeys {
        let input = SymmetricKey(data: secret.bytes)
        let salt = hubID.rawBytes
        func expand(_ info: Data, _ count: Int) -> Data {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: salt, info: info, outputByteCount: count)
                .withUnsafeBytes { Data($0) }
        }
        let identity = expand(identityInfo, 16).map { String(format: "%02x", $0) }.joined()
        return LinkKeys(
            credential: LinkCredential(identity: Data(identity.utf8), key: expand(pskInfo, 32)),
            helloKey: expand(helloInfo, 32)
        )
    }

    /// Binds a hello to this pairing. TLS proves the peer holds some installed key; this proves it
    /// holds the key that belongs to the device ID it claims.
    public func proof(deviceID: UUID, role: DeviceRole) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Self.proofMessage(deviceID: deviceID, role: role), using: SymmetricKey(data: helloKey)))
    }

    public func isValidProof(_ proof: Data, deviceID: UUID, role: DeviceRole) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: Self.proofMessage(deviceID: deviceID, role: role), using: SymmetricKey(data: helloKey))
    }

    private static func proofMessage(deviceID: UUID, role: DeviceRole) -> Data {
        proofLabel + Data(role.rawValue.utf8) + deviceID.rawBytes
    }

    public var description: String { "LinkKeys(redacted)" }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
