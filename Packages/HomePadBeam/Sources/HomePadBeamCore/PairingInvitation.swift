import Foundation
import HomePadCore

public enum PairingInvitationError: Error, Equatable, Sendable {
    case notAnInvitation
    case invalidEncoding
    case unsupportedVersion(UInt8)
    case truncated
    case trailingBytes
    case invalidHubName
    case expired
}

/// What the hub shows as a QR code while pairing mode is open. The code text is
/// `homepad://pair?c=<base64url>` over this layout:
///
///     version (1) | hub ID (16) | expiry, seconds since 1970, big endian (4) | secret (32)
///     | hub name length (1) | hub name, UTF-8
public struct PairingInvitation: Equatable, Sendable {
    public static let version: UInt8 = 1
    public static let host = "pair"
    public static let queryName = "c"
    public static let hubNameByteLimit = 64

    public let hubID: UUID
    public let hubName: String
    public let secret: PairingSecret
    public let expiresAt: Date

    public init(hubID: UUID, hubName: String, secret: PairingSecret, expiresAt: Date) {
        self.hubID = hubID
        self.hubName = Self.fittedName(hubName)
        self.secret = secret
        // The wire format carries whole seconds.
        self.expiresAt = Date(timeIntervalSince1970: Double(Self.wireSeconds(expiresAt)))
    }

    public var keys: LinkKeys {
        LinkKeys.derive(secret: secret, hubID: hubID)
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }

    /// The text to render as a QR code.
    public var code: String {
        var data = Data([Self.version])
        data.append(hubID.rawBytes)
        withUnsafeBytes(of: Self.wireSeconds(expiresAt).bigEndian) { data.append(contentsOf: $0) }
        data.append(secret.bytes)
        let name = Data(hubName.utf8)
        data.append(UInt8(name.count))
        data.append(name)
        return "\(HomePadIdentifiers.urlScheme)://\(Self.host)?\(Self.queryName)=\(Base64URL.encode(data))"
    }

    public static func parse(_ text: String, now: Date) throws(PairingInvitationError) -> PairingInvitation {
        let prefix = "\(HomePadIdentifiers.urlScheme)://\(host)?\(queryName)="
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(prefix) else { throw .notAnInvitation }
        guard let data = Base64URL.decode(String(trimmed.dropFirst(prefix.count))), let first = data.first else {
            throw .invalidEncoding
        }
        guard first == version else { throw .unsupportedVersion(first) }
        let fixedLength = 1 + 16 + 4 + PairingSecret.byteCount + 1
        guard data.count >= fixedLength else { throw .truncated }
        let bytes = [UInt8](data)
        guard let hubID = UUID(rawBytes: Data(bytes[1..<17])),
              let secret = try? PairingSecret(bytes: Data(bytes[21..<53]))
        else { throw .truncated }
        let seconds = bytes[17..<21].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let nameLength = Int(bytes[53])
        guard data.count >= fixedLength + nameLength else { throw .truncated }
        guard data.count == fixedLength + nameLength else { throw .trailingBytes }
        guard nameLength > 0, nameLength <= hubNameByteLimit,
              let name = String(bytes: bytes[54...], encoding: .utf8),
              name == BeamText.sanitizedDeviceName(name, fallback: "")
        else { throw .invalidHubName }
        let invitation = PairingInvitation(hubID: hubID, hubName: name, secret: secret, expiresAt: Date(timeIntervalSince1970: Double(seconds)))
        guard !invitation.isExpired(at: now) else { throw .expired }
        return invitation
    }

    private static func wireSeconds(_ date: Date) -> UInt32 {
        UInt32(min(max(date.timeIntervalSince1970.rounded(.down), 0), Double(UInt32.max)))
    }

    private static func fittedName(_ name: String) -> String {
        var fitted = BeamText.sanitizedDeviceName(name, fallback: BeamSettings.hubName.defaultValue)
        while fitted.utf8.count > hubNameByteLimit {
            fitted.removeLast()
        }
        return fitted
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(allowed.contains), text.count % 4 != 1 else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard.append(String(repeating: "=", count: (4 - standard.count % 4) % 4))
        return Data(base64Encoded: standard)
    }
}

/// An invitation the hub is currently showing, with what only the hub knows about it.
public struct PendingInvitation: Equatable, Sendable {
    public let invitation: PairingInvitation
    /// The household member the scanned device will belong to. Chosen on the hub, never taken
    /// from the device.
    public let profileID: UUID?

    public init(invitation: PairingInvitation, profileID: UUID?) {
        self.invitation = invitation
        self.profileID = profileID
    }
}

/// The hub's pairing mode. One invitation at a time, for one device, with a short life.
public struct PairingSession: Equatable, Sendable {
    public static let defaultLifetime: TimeInterval = 120

    public let lifetime: TimeInterval
    private var pending: PendingInvitation?

    public init(lifetime: TimeInterval = PairingSession.defaultLifetime) {
        self.lifetime = lifetime
    }

    @discardableResult
    public mutating func open(
        hubID: UUID,
        hubName: String,
        profileID: UUID?,
        now: Date,
        random: any RandomSource
    ) throws(PairingSecretError) -> PairingInvitation {
        let invitation = PairingInvitation(
            hubID: hubID,
            hubName: hubName,
            secret: try .generate(using: random),
            expiresAt: now.addingTimeInterval(lifetime)
        )
        pending = PendingInvitation(invitation: invitation, profileID: profileID)
        return invitation
    }

    /// `nil` once the invitation has been used, closed, or has expired.
    public func active(at now: Date) -> PendingInvitation? {
        guard let pending, !pending.invitation.isExpired(at: now) else { return nil }
        return pending
    }

    public func secondsRemaining(at now: Date) -> Int {
        guard let pending = active(at: now) else { return 0 }
        return Int(pending.invitation.expiresAt.timeIntervalSince(now).rounded(.up))
    }

    public mutating func close() {
        pending = nil
    }
}
