import Foundation
import Synchronization

public enum FaceTemplateStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case corruptedTemplate
    case unsupportedFormat(Int)
    /// A Keychain call failed with this `OSStatus`.
    case keychain(status: Int32)
}

/// Where face templates are kept. One template per household member.
public protocol FaceTemplateStore: Sendable {
    func loadAll() throws(FaceTemplateStoreError) -> [FaceTemplate]
    /// Replaces any template already stored for the same profile.
    func save(_ template: FaceTemplate) throws(FaceTemplateStoreError)
    func delete(profileID: UUID) throws(FaceTemplateStoreError)
    func deleteAll() throws(FaceTemplateStoreError)
}

extension FaceTemplateStore {
    /// Deletes templates whose household member no longer exists and returns their profile IDs.
    @discardableResult
    public func deleteOrphans(keeping profileIDs: Set<UUID>) throws(FaceTemplateStoreError) -> [UUID] {
        let orphans = try loadAll().map(\.profileID).filter { !profileIDs.contains($0) }
        for orphan in orphans {
            try delete(profileID: orphan)
        }
        return orphans
    }
}

/// The bytes stored for one template. The format version sits outside the template so a future
/// layout can be detected before any template field is read.
public struct FaceTemplateEnvelope: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    static let accountPrefix = "face-template."

    public let formatVersion: Int
    public let template: FaceTemplate

    public init(template: FaceTemplate) {
        self.formatVersion = Self.currentFormatVersion
        self.template = template
    }

    private struct Header: Decodable {
        let formatVersion: Int
    }

    public func encoded() throws(FaceTemplateStoreError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { throw .encodingFailed }
        return data
    }

    public static func decode(_ data: Data) throws(FaceTemplateStoreError) -> FaceTemplateEnvelope {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw .corruptedTemplate }
        guard header.formatVersion == currentFormatVersion else { throw .unsupportedFormat(header.formatVersion) }
        guard let envelope = try? decoder.decode(FaceTemplateEnvelope.self, from: data) else { throw .corruptedTemplate }
        return envelope
    }

    /// Item name for a member's template inside the shared Keychain service.
    public static func account(for profileID: UUID) -> String {
        accountPrefix + profileID.uuidString
    }

    public static func profileID(fromAccount account: String) -> UUID? {
        guard account.hasPrefix(accountPrefix) else { return nil }
        return UUID(uuidString: String(account.dropFirst(accountPrefix.count)))
    }
}

/// Keeps templates in memory. For tests and previews.
public final class InMemoryFaceTemplateStore: FaceTemplateStore {
    private let templates: Mutex<[UUID: FaceTemplate]>
    private let failure: Mutex<FaceTemplateStoreError?>

    public init(templates: [FaceTemplate] = []) {
        self.templates = Mutex(Dictionary(templates.map { ($0.profileID, $0) }) { _, latest in latest })
        self.failure = Mutex(nil)
    }

    /// Makes every later call throw `error`, to exercise failure paths. Pass `nil` to recover.
    public func failNextCalls(with error: FaceTemplateStoreError?) {
        failure.withLock { $0 = error }
    }

    public func loadAll() throws(FaceTemplateStoreError) -> [FaceTemplate] {
        try throwIfFailing()
        return templates.withLock { $0.values.sorted { $0.profileID.uuidString < $1.profileID.uuidString } }
    }

    public func save(_ template: FaceTemplate) throws(FaceTemplateStoreError) {
        try throwIfFailing()
        templates.withLock { $0[template.profileID] = template }
    }

    public func delete(profileID: UUID) throws(FaceTemplateStoreError) {
        try throwIfFailing()
        templates.withLock { _ = $0.removeValue(forKey: profileID) }
    }

    public func deleteAll() throws(FaceTemplateStoreError) {
        try throwIfFailing()
        templates.withLock { $0.removeAll() }
    }

    private func throwIfFailing() throws(FaceTemplateStoreError) {
        if let error = failure.withLock({ $0 }) {
            throw error
        }
    }
}
