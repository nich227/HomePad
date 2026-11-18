import Foundation
import HomePadCore

public enum LinkMessageError: Error, Equatable, Sendable {
    case truncated
    case unsupportedVersion(UInt8)
    case unknownType(UInt8)
    case invalidHello
    case invalidChannel
    case invalidBody
}

public enum LinkCloseReason: UInt8, Equatable, Sendable {
    case normal = 0
    case unauthorized = 1
    case protocolViolation = 2
    case replaced = 3
    case revoked = 4
    case shuttingDown = 5
    case timedOut = 6
    case unknown = 255
}

/// The first message on a link, in each direction.
public struct LinkHello: Codable, Equatable, Sendable {
    public let device: PeerDevice
    /// See `LinkKeys.proof(deviceID:role:)`.
    public let proof: Data

    public init(device: PeerDevice, proof: Data) {
        self.device = device
        self.proof = proof
    }
}

/// What travels inside a frame: a version byte, a type byte, then the body.
public enum LinkMessage: Equatable, Sendable {
    public static let version: UInt8 = 1
    public static let channelNameByteLimit = 64

    case hello(LinkHello)
    /// The sender is not on the wire. The receiver fills it in from the authenticated peer.
    case envelope(channel: String, payload: Data)
    case ping(UInt64)
    case pong(UInt64)
    case bye(LinkCloseReason)

    private enum Kind: UInt8 {
        case hello = 1, envelope, ping, pong, bye
    }

    public func encoded() throws(LinkMessageError) -> Data {
        var data = Data([Self.version])
        switch self {
        case .hello(let hello):
            data.append(Kind.hello.rawValue)
            guard let body = try? JSONEncoder().encode(hello) else { throw .invalidHello }
            data.append(body)
        case .envelope(let channel, let payload):
            let name = Data(channel.utf8)
            guard !name.isEmpty, name.count <= Self.channelNameByteLimit else { throw .invalidChannel }
            data.append(Kind.envelope.rawValue)
            data.append(UInt8(name.count))
            data.append(name)
            data.append(payload)
        case .ping(let nonce):
            return Self.nonceBody(.ping, nonce)
        case .pong(let nonce):
            return Self.pongBody(nonce)
        case .bye(let reason):
            data.append(Kind.bye.rawValue)
            data.append(reason.rawValue)
        }
        return data
    }

    static func pongBody(_ nonce: UInt64) -> Data {
        nonceBody(.pong, nonce)
    }

    private static func nonceBody(_ kind: Kind, _ nonce: UInt64) -> Data {
        var data = Data([version, kind.rawValue])
        withUnsafeBytes(of: nonce.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    public init(decoding data: Data) throws(LinkMessageError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw .truncated }
        guard bytes[0] == Self.version else { throw .unsupportedVersion(bytes[0]) }
        guard let kind = Kind(rawValue: bytes[1]) else { throw .unknownType(bytes[1]) }
        let body = bytes[2...]
        switch kind {
        case .hello:
            guard let hello = try? JSONDecoder().decode(LinkHello.self, from: Data(body)) else { throw .invalidHello }
            self = .hello(hello)
        case .envelope:
            guard let length = body.first.map(Int.init), length > 0, length <= Self.channelNameByteLimit,
                  body.count >= 1 + length,
                  let channel = String(bytes: body.dropFirst().prefix(length), encoding: .utf8)
            else { throw .invalidChannel }
            self = .envelope(channel: channel, payload: Data(body.dropFirst(1 + length)))
        case .ping, .pong:
            guard body.count == 8 else { throw .invalidBody }
            let nonce = body.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            self = kind == .ping ? .ping(nonce) : .pong(nonce)
        case .bye:
            guard body.count == 1, let code = body.first else { throw .invalidBody }
            self = .bye(LinkCloseReason(rawValue: code) ?? .unknown)
        }
    }
}
