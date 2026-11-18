import Foundation
import HomePadCore

public enum LinkLimits {
    /// Frames are this small until the peer has been authenticated by its hello.
    public static let helloFrameLimit = 4 * 1024
    public static let frameLimit = 1024 * 1024
    public static let maximumConnections = 16
    public static let maximumUnauthenticatedConnections = 4
    public static let handshakeTimeout: TimeInterval = 10
    public static let receiveChunkSize = 64 * 1024

    /// Whether the hub should take one more inbound connection.
    public static func canAccept(total: Int, unauthenticated: Int) -> Bool {
        total < maximumConnections && unauthenticated < maximumUnauthenticatedConnections
    }
}

public enum LinkSessionEvent: Equatable, Sendable {
    /// The peer's hello. The owner checks it and calls `establish(peerID:)` or closes the link.
    case hello(LinkHello)
    case envelope(PeerEnvelope)
    /// Framed bytes to write back to the peer.
    case reply(Data)
    case pong(UInt64)
    /// The link must be closed. Nothing further is processed.
    case close(LinkCloseReason)
}

/// The state of one connection after TLS. It turns received bytes into events and enforces the
/// order: a hello first, and nothing else until the owner has accepted it.
public struct LinkSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case awaitingHello
        case authenticating
        case established(UUID)
        case closed
    }

    public private(set) var phase: Phase = .awaitingHello
    private var decoder: FrameDecoder
    private let frameLimit: Int

    public init(helloFrameLimit: Int = LinkLimits.helloFrameLimit, frameLimit: Int = LinkLimits.frameLimit) {
        self.decoder = FrameDecoder(limit: helloFrameLimit)
        self.frameLimit = frameLimit
    }

    public mutating func receive(_ bytes: Data) -> [LinkSessionEvent] {
        guard phase != .closed else { return [] }
        decoder.append(bytes)
        if phase == .authenticating {
            guard decoder.bufferedByteCount <= frameLimit + FrameCodec.headerLength else {
                return close(.protocolViolation)
            }
            return []
        }
        return drain()
    }

    /// Accepts the peer's hello. Returns the events for anything the peer sent right behind it.
    public mutating func establish(peerID: UUID) -> [LinkSessionEvent] {
        guard phase == .authenticating else { return [] }
        phase = .established(peerID)
        decoder.limit = frameLimit
        return drain()
    }

    public mutating func close() {
        phase = .closed
    }

    /// A complete frame for `message`, ready to write.
    public static func frame(_ message: LinkMessage, limit: Int = LinkLimits.frameLimit) throws(LinkFramingError) -> Data {
        let body: Data
        do {
            body = try message.encoded()
        } catch {
            throw .message(error)
        }
        do {
            return try FrameCodec.encode(body, limit: limit)
        } catch {
            throw .frame(error)
        }
    }

    private mutating func drain() -> [LinkSessionEvent] {
        var events: [LinkSessionEvent] = []
        var more = true
        while more {
            let step = processNextFrame()
            events += step.events
            more = step.more
        }
        return events
    }

    private mutating func processNextFrame() -> (events: [LinkSessionEvent], more: Bool) {
        let body: Data
        do {
            guard let next = try decoder.next() else { return ([], false) }
            body = next
        } catch {
            return (close(.protocolViolation), false)
        }
        guard let message = try? LinkMessage(decoding: body) else {
            return (close(.protocolViolation), false)
        }
        switch (phase, message) {
        case (.awaitingHello, .hello(let hello)):
            phase = .authenticating
            return ([.hello(hello)], false)
        case (.established(let peer), .envelope(let channel, let payload)):
            return ([.envelope(PeerEnvelope(channel: channel, sender: peer, payload: payload))], true)
        case (.established, .ping(let nonce)):
            return ([.reply(FrameCodec.prefixed(LinkMessage.pongBody(nonce)))], true)
        case (.established, .pong(let nonce)):
            return ([.pong(nonce)], true)
        case (_, .bye(let reason)):
            return (close(reason), false)
        default:
            return (close(.protocolViolation), false)
        }
    }

    private mutating func close(_ reason: LinkCloseReason) -> [LinkSessionEvent] {
        phase = .closed
        return [.close(reason)]
    }
}

public enum LinkFramingError: Error, Equatable, Sendable {
    case message(LinkMessageError)
    case frame(FrameError)
}
