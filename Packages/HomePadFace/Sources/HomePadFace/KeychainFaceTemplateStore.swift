import Foundation
import HomePadCore
import HomePadFaceCore
import Security

/// Keeps face templates in the Keychain as generic passwords: one item per household member,
/// readable only while the device is unlocked, never synced, never restored to another device.
public struct KeychainFaceTemplateStore: FaceTemplateStore {
    private let service: String

    public init(service: String = HomePadIdentifiers.keychainService) {
        self.service = service
    }

    public func loadAll() throws(FaceTemplateStoreError) -> [FaceTemplate] {
        var templates: [FaceTemplate] = []
        for account in try accounts() {
            var query = baseQuery(account: account)
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess else { throw .keychain(status: status) }
            // An item that cannot be read as a template is skipped, so one damaged item does not
            // lock everyone else out of recognition.
            if let data = result as? Data, let envelope = try? FaceTemplateEnvelope.decode(data) {
                templates.append(envelope.template)
            }
        }
        return templates
    }

    public func save(_ template: FaceTemplate) throws(FaceTemplateStoreError) {
        let data = try FaceTemplateEnvelope(template: template).encoded()
        let query = baseQuery(account: FaceTemplateEnvelope.account(for: template.profileID))
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(update) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .keychain(status: status) }
    }

    public func delete(profileID: UUID) throws(FaceTemplateStoreError) {
        let status = SecItemDelete(baseQuery(account: FaceTemplateEnvelope.account(for: profileID)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
    }

    public func deleteAll() throws(FaceTemplateStoreError) {
        // The service is shared with other features, so items are removed one by one by name.
        for account in try accounts() {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// Account names of the face template items in the service.
    private func accounts() throws(FaceTemplateStoreError) -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw .keychain(status: status) }
        let items = result as? [[String: Any]] ?? []
        return items
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { FaceTemplateEnvelope.profileID(fromAccount: $0) != nil }
    }
}
