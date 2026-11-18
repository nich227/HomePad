import Foundation

public protocol ProfileStore: Sendable {
    func load() throws -> [HouseholdProfile]
    func save(_ profiles: [HouseholdProfile]) throws
}

/// Keeps the household list as JSON on disk. Face templates and pairing keys live in the Keychain,
/// not here.
public struct FileProfileStore: ProfileStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/HomePad/profiles.json`
    public static func applicationSupport(fileManager: FileManager = .default) throws -> FileProfileStore {
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HomePad", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileProfileStore(url: directory.appendingPathComponent("profiles.json"))
    }

    public func load() throws -> [HouseholdProfile] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HouseholdProfile].self, from: Data(contentsOf: url))
    }

    public func save(_ profiles: [HouseholdProfile]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(profiles).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

public final class InMemoryProfileStore: ProfileStore, @unchecked Sendable {
    private let lock = NSLock()
    private var profiles: [HouseholdProfile]

    public init(profiles: [HouseholdProfile] = []) {
        self.profiles = profiles
    }

    public func load() throws -> [HouseholdProfile] {
        lock.withLock { profiles }
    }

    public func save(_ profiles: [HouseholdProfile]) throws {
        lock.withLock { self.profiles = profiles }
    }
}
