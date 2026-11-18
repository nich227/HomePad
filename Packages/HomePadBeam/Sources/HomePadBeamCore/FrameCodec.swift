import Foundation

public enum FrameError: Error, Equatable, Sendable {
    case empty
    case tooLarge(declared: Int, limit: Int)
    /// The decoder already failed. A stream cannot be resynchronized after a bad length.
    case closed
}

/// Length-prefixed framing: a 4 byte big endian body length, then the body.
public enum FrameCodec {
    public static let headerLength = 4

    public static func encode(_ body: Data, limit: Int) throws(FrameError) -> Data {
        guard !body.isEmpty else { throw .empty }
        guard body.count <= limit else { throw .tooLarge(declared: body.count, limit: limit) }
        return prefixed(body)
    }

    static func prefixed(_ body: Data) -> Data {
        var frame = Data(capacity: headerLength + body.count)
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }
}

/// Reassembles frames from a byte stream cut at arbitrary points.
public struct FrameDecoder: Sendable {
    /// The largest body accepted. A larger declared length fails as soon as the header is read,
    /// before any of the body is buffered.
    public var limit: Int
    private var buffer = Data()
    private var failed = false

    public init(limit: Int) {
        self.limit = limit
    }

    public var bufferedByteCount: Int { buffer.count }

    public mutating func append(_ chunk: Data) {
        guard !failed else { return }
        buffer.append(chunk)
    }

    /// The next complete frame body, or `nil` when more bytes are needed.
    public mutating func next() throws(FrameError) -> Data? {
        guard !failed else { throw .closed }
        guard buffer.count >= FrameCodec.headerLength else { return nil }
        let length = buffer.prefix(FrameCodec.headerLength).reduce(0) { $0 << 8 | Int($1) }
        guard length > 0 else {
            fail()
            throw .empty
        }
        guard length <= limit else {
            fail()
            throw .tooLarge(declared: length, limit: limit)
        }
        let total = FrameCodec.headerLength + length
        guard buffer.count >= total else { return nil }
        let body = Data(buffer.dropFirst(FrameCodec.headerLength).prefix(length))
        buffer = Data(buffer.dropFirst(total))
        return body
    }

    private mutating func fail() {
        failed = true
        buffer = Data()
    }
}
