import Foundation
import Observation

/// How far the person in front of the hub is. Far is across the room: large numbers only. Mid
/// is on approach: labels and thumbnails appear. Near is within reach: full controls.
public enum Proximity: String, Codable, Sendable, CaseIterable {
    case far, mid, near
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
///
/// The audience is the active member, or the guest when nobody is active. Three things are
/// decided here once, for every package:
///
/// - What to personalize: `activeProfile`.
/// - Whether personal content may show: `isPersonalContentUnlocked`. It turns false the moment
///   the camera can no longer vouch for the member.
/// - When the audience signed out: `audienceGeneration` changes, and only then. A package that
///   keeps anything open for the audience (pages, drafts, a playing scene) closes it when this
///   value changes and at no other time.
///
/// Losing sight of someone is not a sign out. When the camera stops seeing the audience, or
/// sees a face it cannot judge, the audience lingers for `lingerDuration`: a member stays the
/// active profile with personal content locked, and `lingerDeadline` says when the wait ends.
/// The same person coming back ends the wait with nothing lost. The wait ends in a sign out
/// when the deadline passes, and at once when the hub is locked, someone switches profiles by
/// hand, another member is recognized, or the camera judges a face and it is not the member's.
/// A guest and a member picked by hand cannot be told from any other unrecognized face, so for
/// them any face coming back continues the session.
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
    /// When the audience that the camera lost sight of counts as gone. `nil` when nobody is
    /// lingering. Call `endLingerIfDue(at:)` on a timer so the deadline takes effect.
    public private(set) var lingerDeadline: Date?
    /// Changes exactly when the audience signs out. See the type's description.
    public private(set) var audienceGeneration = 0

    /// When true, personal content also needs the member's paired device nearby.
    public var requiresCompanionForPersonalContent: Bool
    /// How long the audience stays signed in after the camera loses sight of them, in seconds.
    /// Zero or less means not at all.
    public var lingerDuration: TimeInterval
    /// `nil` means no limit.
    public let profileLimit: Int?

    private let store: any ProfileStore
    /// Whether the lingering member was activated by the camera, so the activation ends with
    /// the wait. A member picked by hand stays picked.
    private var lingerEndsActivation = false

    public init(
        store: any ProfileStore,
        profileLimit: Int? = nil,
        requiresCompanionForPersonalContent: Bool = false,
        lingerDuration: TimeInterval = 0
    ) {
        self.store = store
        self.profileLimit = profileLimit
        self.requiresCompanionForPersonalContent = requiresCompanionForPersonalContent
        self.lingerDuration = lingerDuration
        self.profiles = (try? store.load()) ?? []
    }

    public var activeProfile: HouseholdProfile? {
        activation.profileID.flatMap { id in profiles.first { $0.id == id } }
    }

    public var isGuest: Bool { activeProfile == nil }

    /// True while the camera has lost sight of the audience and they have not signed out yet.
    public var isLingering: Bool { lingerDeadline != nil }

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
        if cameraMatchedProfileID == id { clearCameraMatch() }
        if activation.profileID == id { activate(.none) }
        try store.save(profiles)
    }

    // MARK: Presence

    public func faceRecognized(profileID: UUID, proximity: Proximity, at date: Date = Date()) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        endLingerIfDue(at: date)
        isSomeonePresent = true
        self.proximity = proximity
        clearCameraMatch()
        activate(.face(profileID, at: date))
    }

    /// The camera matched an enrolled member but could not prove the face was live, for example
    /// on an iPad with no depth camera. Personalizes without unlocking personal content.
    public func faceMatchedWithoutLiveness(profileID: UUID, proximity: Proximity, at date: Date = Date()) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        endLingerIfDue(at: date)
        isSomeonePresent = true
        self.proximity = proximity
        if isConfirmedByDeviceBiometrics, cameraMatchedProfileID == profileID, activation.profileID == profileID {
            return
        }
        cameraMatchedProfileID = profileID
        isConfirmedByDeviceBiometrics = false
        activate(.manual(profileID))
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

    /// Takes back what the device's biometrics vouched for, because the camera has since seen
    /// another member. The member stays active and can confirm again. Nobody signs out.
    public func dropDeviceBiometricConfirmation() {
        guard isConfirmedByDeviceBiometrics, let cameraMatchedProfileID else { return }
        isConfirmedByDeviceBiometrics = false
        activation = .manual(cameraMatchedProfileID)
    }

    /// The camera judged a face and it matches no enrolled profile. Someone else is in front of
    /// the hub, so a member the camera activated signs out at once, lingering or not. A guest or
    /// a member picked by hand carries on: this face may well be theirs.
    public func unknownFacePresent(proximity: Proximity, at date: Date = Date()) {
        endLingerIfDue(at: date)
        isSomeonePresent = true
        self.proximity = proximity
        if cameraActivatedProfileID != nil || lingerEndsActivation {
            clearCameraMatch()
            activate(.none)
        } else {
            lingerDeadline = nil
        }
    }

    /// Someone is in view but the camera cannot judge the face: it is turned away, too dark, or
    /// too blurred. It may still be the member, so a member the camera activated starts to
    /// linger, with personal content locked, and one who is already lingering keeps the same
    /// deadline. For a guest or a member picked by hand, someone being there continues the
    /// session.
    public func faceUnreadable(proximity: Proximity, at date: Date = Date()) {
        endLingerIfDue(at: date)
        isSomeonePresent = true
        self.proximity = proximity
        if let profileID = cameraActivatedProfileID {
            cameraLostSight(of: profileID, at: date)
        } else if !lingerEndsActivation {
            lingerDeadline = nil
        }
    }

    /// Nobody is in front of the camera any more. Whoever was there starts to linger. A second
    /// call while nobody is there changes nothing, so the deadline is not pushed back.
    public func presenceLost(at date: Date = Date()) {
        endLingerIfDue(at: date)
        let wasPresent = isSomeonePresent
        isSomeonePresent = false
        proximity = .far
        if let profileID = cameraActivatedProfileID {
            cameraLostSight(of: profileID, at: date)
        } else if wasPresent, lingerDeadline == nil {
            if lingerDuration > 0 {
                lingerDeadline = date.addingTimeInterval(lingerDuration)
            } else {
                audienceGeneration += 1
            }
        }
    }

    /// Signs the lingering audience out once `lingerDeadline` has passed. The app calls this on
    /// a timer, about once a second, while the hub runs. Returns whether someone signed out.
    @discardableResult
    public func endLingerIfDue(at date: Date = Date()) -> Bool {
        guard let lingerDeadline, date >= lingerDeadline else { return false }
        if lingerEndsActivation {
            activation = .none
        }
        self.lingerDeadline = nil
        lingerEndsActivation = false
        audienceGeneration += 1
        return true
    }

    public func switchManually(to profileID: UUID) throws {
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw HouseholdError.unknownProfile(profileID)
        }
        clearCameraMatch()
        activate(.manual(profileID))
    }

    /// Locks the hub. Whoever the audience was, the guest included, signs out.
    public func lock() {
        clearCameraMatch()
        lingerDeadline = nil
        lingerEndsActivation = false
        activation = .none
        audienceGeneration += 1
    }

    public func setCompanionPresent(_ present: Bool, for profileID: UUID) {
        if present, profiles.contains(where: { $0.id == profileID }) {
            profilesWithCompanionPresent.insert(profileID)
        } else {
            profilesWithCompanionPresent.remove(profileID)
        }
    }

    /// The member the camera activated: by a live face, or by a match that awaits or has the
    /// device's biometrics. `nil` for a guest, a member picked by hand, and a lingering member.
    private var cameraActivatedProfileID: UUID? {
        if case .face(let id, _) = activation { return id }
        if let cameraMatchedProfileID, activation == .manual(cameraMatchedProfileID) { return cameraMatchedProfileID }
        return nil
    }

    /// Locks personal content at once. The member then lingers, or signs out when lingering is
    /// off.
    private func cameraLostSight(of profileID: UUID, at date: Date) {
        clearCameraMatch()
        guard lingerDuration > 0 else {
            activate(.none)
            return
        }
        activation = .manual(profileID)
        lingerDeadline = date.addingTimeInterval(lingerDuration)
        lingerEndsActivation = true
    }

    /// Makes `next` the activation and ends any lingering. A change of person signs the
    /// previous audience out.
    private func activate(_ next: ProfileActivation) {
        if next.profileID != activation.profileID {
            audienceGeneration += 1
        }
        lingerDeadline = nil
        lingerEndsActivation = false
        activation = next
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
