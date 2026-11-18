import Foundation
import Observation

/// How far the person in front of the hub is. Faces show less detail when far.
public enum Proximity: String, Codable, Sendable {
    case far, near
}

/// How the active profile was selected. Personal content needs `face`.
public enum ProfileActivation: Equatable, Sendable {
    case none
    /// Picked by hand. Personalization applies, personal content stays locked.
    case manual(UUID)
    /// Recognized by the camera.
    case face(UUID, at: Date)

    public var profileID: UUID? {
        switch self {
        case .none: nil
        case .manual(let id): id
        case .face(let id, _): id
        }
    }
}

public enum HouseholdError: Error, Equatable, Sendable {
    case profileLimitReached(Int)
    case unknownProfile(UUID)
    case emptyName
}

/// The household and who is in front of the hub right now. Feature packages read this to decide
/// what to show. The face package writes recognition results into it through the app.
@MainActor
@Observable
public final class HouseholdSession {
    public private(set) var profiles: [HouseholdProfile]
    public private(set) var activation: ProfileActivation = .none
    public private(set) var proximity: Proximity = .far
    /// Whether anyone at all is in front of the camera.
    public private(set) var isSomeonePresent = false
    /// Profiles whose paired companion device is connected and was unlocked recently.
    public private(set) var profilesWithCompanionPresent: Set<UUID> = []
    /// The member the camera matched without proof that a live face was in front of it. That
    /// match personalizes the hub. It unlocks personal content only after the device's own
    /// biometrics confirm someone enrolled on the device is present.
    public private(set) var cameraMatchedProfileID: UUID?
    public private(set) var isConfirmedByDeviceBiometrics = false

    /// When true, personal content also needs the member's paired device nearby.
    public var requiresCompanionForPersonalContent: Bool
    /// `nil` means no limit.
    public let profileLimit: Int?

    private let store: any ProfileStore

    public init(
        store: any ProfileStore,
        profileLimit: Int? = nil,
        requiresCompanionForPersonalContent: Bool = false
    ) {
        self.store = store
        self.profileLimit = profileLimit
        self.requiresCompanionForPersonalContent = requiresCompanionForPersonalContent
        self.profiles = (try? store.load()) ?? []
    }

    public var activeProfile: HouseholdProfile? {
        activation.profileID.flatMap { id in profiles.first { $0.id == id } }
    }

    public var isGuest: Bool { activeProfile == nil }

    /// True while a camera match is waiting for the device's biometrics to unlock personal content.
    public var canConfirmWithDeviceBiometrics: Bool {
        guard let cameraMatchedProfileID else { return false }
        return activation == .manual(cameraMatchedProfileID)
    }

    /// Personal content (messages, calendar, personal widgets) shows only for a face match.
    public var isPersonalContentUnlocked: Bool {
        guard case .face(let id, _) = activation, profiles.contains(where: { $0.id == id }) else {
            return false
        }
        return !requiresCompanionForPersonalContent || profilesWithCompanionPresent.contains(id)
    }

    // MARK: Profiles

    @discardableResult
    public func addProfile(name: String, tint: RainbowTint? = nil, symbolName: String = "person.crop.circle.fill") throws -> HouseholdProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HouseholdError.emptyName }
        if let profileLimit, profiles.count >= profileLimit {
            throw HouseholdError.profileLimitReached(profileLimit)
        }
        let profile = HouseholdProfile(name: trimmed, tint: tint ?? nextTint(), symbolName: symbolName)
        profiles.append(profile)
        try store.save(profiles)
        return profile
    }

    public func updateProfile(_ profile: HouseholdProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw HouseholdError.unknownProfile(profile.id)
        }
        profiles[index] = profile
        try store.save(profiles)
    }

    public func removeProfile(id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw HouseholdError.unknownProfile(id) }
        profiles.removeAll { $0.id == id }
        profilesWithCompanionPresent.remove(id)
        if activation.profileID == id { activation = .none }
        if cameraMatchedProfileID == id { clearCameraMatch() }
        try store.save(profiles)
    }

    // MARK: Presence

    public func faceRecognized(profileID: UUID, proximity: Proximity, at date: Date = Date()) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        isSomeonePresent = true
        self.proximity = proximity
        clearCameraMatch()
        activation = .face(profileID, at: date)
    }

    /// The camera matched an enrolled member but could not prove the face was live, for example
    /// on an iPad with no depth camera. Personalizes without unlocking personal content.
    public func faceMatchedWithoutLiveness(profileID: UUID, proximity: Proximity) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        isSomeonePresent = true
        self.proximity = proximity
        if isConfirmedByDeviceBiometrics, cameraMatchedProfileID == profileID, activation.profileID == profileID {
            return
        }
        cameraMatchedProfileID = profileID
        isConfirmedByDeviceBiometrics = false
        activation = .manual(profileID)
    }

    /// Call after the device's biometrics (Touch ID) succeed. Unlocks personal content for the
    /// camera-matched member until they leave. Returns false when no camera match is waiting.
    @discardableResult
    public func confirmWithDeviceBiometrics(at date: Date = Date()) -> Bool {
        guard canConfirmWithDeviceBiometrics, let cameraMatchedProfileID else { return false }
        isConfirmedByDeviceBiometrics = true
        activation = .face(cameraMatchedProfileID, at: date)
        return true
    }

    /// Someone is there but matches no enrolled profile. A face-activated profile locks.
    public func unknownFacePresent(proximity: Proximity) {
        isSomeonePresent = true
        self.proximity = proximity
        endCameraDrivenActivation()
    }

    /// Nobody is in front of the camera any more.
    public func presenceLost() {
        isSomeonePresent = false
        proximity = .far
        endCameraDrivenActivation()
    }

    public func switchManually(to profileID: UUID) throws {
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw HouseholdError.unknownProfile(profileID)
        }
        clearCameraMatch()
        activation = .manual(profileID)
    }

    public func lock() {
        clearCameraMatch()
        activation = .none
    }

    public func setCompanionPresent(_ present: Bool, for profileID: UUID) {
        if present, profiles.contains(where: { $0.id == profileID }) {
            profilesWithCompanionPresent.insert(profileID)
        } else {
            profilesWithCompanionPresent.remove(profileID)
        }
    }

    /// Ends what the camera started. A profile someone picked by hand stays.
    private func endCameraDrivenActivation() {
        if case .face = activation {
            activation = .none
        } else if let cameraMatchedProfileID, activation == .manual(cameraMatchedProfileID) {
            activation = .none
        }
        clearCameraMatch()
    }

    private func clearCameraMatch() {
        cameraMatchedProfileID = nil
        isConfirmedByDeviceBiometrics = false
    }

    private func nextTint() -> RainbowTint {
        let all = RainbowTint.allCases
        return all[profiles.count % all.count]
    }
}
