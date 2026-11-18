import Foundation
import HomePadBeamCore
import HomePadCore
import Security

/// Keeps pairings and this device's ID in the Keychain, in the app group so the share extension
/// reads the same items. Items never leave the device and are readable only while it is unlocked.
public struct KeychainPairingStore: PairingStore {
    private let pairingService: String
    private let identityService: String
    private let accessGroup: String?
    private static let identityAccount = "local-device"

    /// - Parameter accessGroup: Pass `nil` only where no app group entitlement exists, such as a
    ///   unit test host.
    public init(
        service: String = HomePadIdentifiers.keychainService,
        accessGroup: String? = HomePadIdentifiers.appGroup
    ) {
        self.pairingService = service + ".beam.pairing"
        self.identityService = service + ".beam.identity"
        self.accessGroup = accessGroup
    }

    public func devices() throws(PairingStoreError) -> [PairedDevice] {
        var query = baseQuery(service: pairingService)
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        let accounts = (result as? [[CFString: Any]] ?? []).compactMap { $0[kSecAttrAccount] as? String }
        var devices: [PairedDevice] = []
        for account in accounts {
            guard let data = try read(service: pairingService, account: account) else { continue }
            guard let device = try? JSONDecoder().decode(PairedDevice.self, from: data) else { throw .corrupted }
            devices.append(device)
        }
        return devices.sorted { ($0.pairedAt, $0.id.uuidString) < ($1.pairedAt, $1.id.uuidString) }
    }

    public func save(_ device: PairedDevice) throws(PairingStoreError) {
        guard let data = try? JSONEncoder().encode(device) else { throw .corrupted }
        try write(data, service: pairingService, account: device.id.uuidString)
    }

    public func remove(id: UUID) throws(PairingStoreError) {
        var query = baseQuery(service: pairingService)
        query[kSecAttrAccount] = id.uuidString
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    public func localDeviceID() throws(PairingStoreError) -> UUID? {
        guard let data = try read(service: identityService, account: Self.identityAccount) else { return nil }
        guard let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { throw .corrupted }
        return id
    }

    public func saveLocalDeviceID(_ id: UUID) throws(PairingStoreError) {
        try write(Data(id.uuidString.utf8), service: identityService, account: Self.identityAccount)
    }

    private func baseQuery(service: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    private func read(service: String, account: String) throws(PairingStoreError) -> Data? {
        var query = baseQuery(service: service)
        query[kSecAttrAccount] = account
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw .corrupted }
        return data
    }

    private func write(_ data: Data, service: String, account: String) throws(PairingStoreError) {
        var query = baseQuery(service: service)
        query[kSecAttrAccount] = account
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(update) { _, new in new }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    private func check(_ status: OSStatus) throws(PairingStoreError) {
        switch status {
        case errSecSuccess: return
        case errSecMissingEntitlement: throw .missingEntitlement
        default: throw .unavailable(status)
        }
    }
}
