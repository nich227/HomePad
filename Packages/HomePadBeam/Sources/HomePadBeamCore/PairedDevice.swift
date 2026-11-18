import Foundation
import HomePadCore

/// One pairing, as stored on either side. On the hub `device` is the companion; on a companion
/// `device` is the hub.
public struct PairedDevice: Identifiable, Codable, Equatable, Sendable {
    public var device: PeerDevice
    public let secret: PairingSecret
    /// The hub of this pairing. It salts the key derivation.
    public let hubID: UUID
    public let pairedAt: Date
    /// Beams from this device that someone at the hub chose to open.
    public var approvedBeamCount: Int

    public init(device: PeerDevice, secret: PairingSecret, hubID: UUID, pairedAt: Date, approvedBeamCount: Int = 0) {
        self.device = device
        self.secret = secret
        self.hubID = hubID
        self.pairedAt = pairedAt
        self.approvedBeamCount = approvedBeamCount
    }

    public var id: UUID { device.id }

    public var keys: LinkKeys {
        LinkKeys.derive(secret: secret, hubID: hubID)
    }
}

public enum PairingStoreError: Error, Equatable, Sendable {
    /// The store refused the operation. The value is the underlying status code.
    case unavailable(Int32)
    case missingEntitlement
    case corrupted
}

/// Where pairings and this device's own ID live. The shipping implementation is the Keychain.
public protocol PairingStore: Sendable {
    func devices() throws(PairingStoreError) -> [PairedDevice]
    func save(_ device: PairedDevice) throws(PairingStoreError)
    func remove(id: UUID) throws(PairingStoreError)
    func localDeviceID() throws(PairingStoreError) -> UUID?
    func saveLocalDeviceID(_ id: UUID) throws(PairingStoreError)
}

extension PairingStore {
    /// This device's stable ID, created on first use.
    public func loadOrCreateLocalDeviceID(makeID: () -> UUID = { UUID() }) throws(PairingStoreError) -> UUID {
        if let existing = try localDeviceID() { return existing }
        let id = makeID()
        try saveLocalDeviceID(id)
        return id
    }

    public func device(id: UUID) throws(PairingStoreError) -> PairedDevice? {
        try devices().first { $0.id == id }
    }
}

public final class InMemoryPairingStore: PairingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UUID: PairedDevice] = [:]
    private var localID: UUID?
    private var failure: PairingStoreError?

    public init(devices: [PairedDevice] = [], localDeviceID: UUID? = nil) {
        for device in devices {
            stored[device.id] = device
        }
        localID = localDeviceID
    }

    /// Makes every later call throw, to exercise failure paths.
    public func failNextCalls(with error: PairingStoreError?) {
        lock.withLock { failure = error }
    }

    public func devices() throws(PairingStoreError) -> [PairedDevice] {
        try perform { stored.values.sorted { ($0.pairedAt, $0.id.uuidString) < ($1.pairedAt, $1.id.uuidString) } }
    }

    public func save(_ device: PairedDevice) throws(PairingStoreError) {
        try perform { stored[device.id] = device }
    }

    public func remove(id: UUID) throws(PairingStoreError) {
        try perform { _ = stored.removeValue(forKey: id) }
    }

    public func localDeviceID() throws(PairingStoreError) -> UUID? {
        try perform { localID }
    }

    public func saveLocalDeviceID(_ id: UUID) throws(PairingStoreError) {
        try perform { localID = id }
    }

    private func perform<T>(_ body: () -> T) throws(PairingStoreError) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return body()
    }
}
