import Foundation

public enum SnapshotCodecError: Error, Equatable, Sendable {
    case corrupt
    case unsupportedVersion(Int)
}

/// Wraps a payload with a schema version so a file written by a different schema is rejected
/// instead of being misread.
public struct VersionedCodec<Payload: Codable & Sendable>: Sendable {
    public let version: Int

    public init(version: Int) {
        self.version = version
    }

    private struct Envelope: Codable {
        let version: Int
        let payload: Payload
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    public func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: version, payload: payload))
    }

    public func decode(_ data: Data) throws(SnapshotCodecError) -> Payload {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { throw .corrupt }
        guard probe.version == version else { throw .unsupportedVersion(probe.version) }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw .corrupt }
        return envelope.payload
    }
}

public enum SnapshotStoreError: Error, Equatable, Sendable {
    case unreadable
    case unwritable
}

/// One blob of app state on disk. Holds layouts, timers, and alarms; never secrets.
public protocol SnapshotStore: Sendable {
    func load() throws(SnapshotStoreError) -> Data?
    func save(_ data: Data) throws(SnapshotStoreError)
    func remove() throws(SnapshotStoreError)
}

public struct FileSnapshotStore: SnapshotStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws(SnapshotStoreError) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        return data
    }

    public func save(_ data: Data) throws(SnapshotStoreError) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A running timer must be readable when the hub relaunches before the first unlock ends.
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        guard (try? data.write(to: url, options: options)) != nil else { throw .unwritable }
    }

    public func remove() throws(SnapshotStoreError) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard (try? FileManager.default.removeItem(at: url)) != nil else { throw .unwritable }
    }
}

public final class InMemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func load() throws(SnapshotStoreError) -> Data? {
        lock.withLock { data }
    }

    public func save(_ data: Data) throws(SnapshotStoreError) {
        lock.withLock { self.data = data }
    }

    public func remove() throws(SnapshotStoreError) {
        lock.withLock { data = nil }
    }
}
