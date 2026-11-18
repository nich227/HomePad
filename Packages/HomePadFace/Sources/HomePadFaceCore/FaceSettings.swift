import Foundation
import HomePadCore

/// Face recognition preferences. The user changes them in the system Settings app; the app only
/// reads them.
public enum FaceSettings {
    public static let pane = "Face Recognition"

    public static let recognitionEnabled = SettingKey<Bool>("face.recognitionEnabled", default: true)
    public static let indeterminateLivenessPersonalizes = SettingKey<Bool>("face.indeterminateLivenessPersonalizes", default: true)
    public static let touchIDUnlock = SettingKey<Bool>("face.touchIDUnlock", default: true)
    public static let lockDelaySeconds = SettingKey<Int>("face.lockDelaySeconds", default: 3)
    public static let nearDistance = SettingKey<String>("face.nearDistance", default: NearDistance.standard.rawValue)

    public static let matchStrictness = SettingKey<String>("face.matchStrictness", default: MatchStrictness.standard.rawValue)

    public static let lockDelayOptions = [1, 3, 5, 10, 30]

    public enum NearDistance: String, CaseIterable, Sendable {
        case closer, standard, farther

        public var policy: ProximityPolicy {
            switch self {
            case .closer: .closer
            case .standard: .standard
            case .farther: .farther
            }
        }
    }

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(
            recognitionEnabled,
            title: "Recognize Faces",
            pane: pane,
            footer: "When on, the hub uses its front camera to recognize enrolled household members. Face data stays on this device. When off, the camera is not used for recognition and everyone gets the guest experience unless a profile is picked by hand."
        ),
        SettingDescriptor(
            indeterminateLivenessPersonalizes,
            title: "Personalize Without Depth Check",
            pane: pane,
            footer: "When the camera cannot confirm that a recognized face is a real person (no depth camera, or the person is too far away), the hub may still switch to that person's layout. Personal content stays locked either way. Turn this off to treat such a face as a guest."
        ),
        SettingDescriptor(
            touchIDUnlock,
            title: "Unlock with Touch ID",
            pane: pane,
            footer: "On an iPad without Face ID, after the camera recognizes a household member, any fingerprint enrolled on this iPad unlocks that member's personal content until they leave. Touch ID confirms that someone who can unlock this iPad is present, not which person. The iPad passcode is not accepted. Needs Personalize Without Depth Check to be on."
        ),
        SettingDescriptor(
            matchStrictness,
            title: "Match Strictness",
            pane: pane,
            options: [
                .init(title: "Relaxed", value: MatchStrictness.relaxed.rawValue),
                .init(title: "Standard", value: MatchStrictness.standard.rawValue),
                .init(title: "Strict", value: MatchStrictness.strict.rawValue),
            ],
            footer: "How sure the hub must be before it accepts a face as a household member. Relaxed recognizes people more readily and is more likely to mistake one person for another. Strict does the opposite."
        ),
        SettingDescriptor(
            lockDelaySeconds,
            title: "Lock After Face Is Lost",
            pane: pane,
            options: lockDelayOptions.map { .init(title: $0 == 1 ? "1 second" : "\($0) seconds", value: String($0)) },
            footer: "How long the hub waits after it stops seeing the recognized person before it locks their profile."
        ),
        SettingDescriptor(
            nearDistance,
            title: "Detail Distance",
            pane: pane,
            options: [
                .init(title: "Closer", value: NearDistance.closer.rawValue),
                .init(title: "Standard", value: NearDistance.standard.rawValue),
                .init(title: "Farther", value: NearDistance.farther.rawValue),
            ],
            footer: "The hub shows the most detail to someone within arm's reach, less at mid range, and the least from across the room. Standard puts arm's reach at about 1 m (3 ft) and across the room at about 2.5 m (8 ft). Closer moves both about a quarter nearer to the screen, and Farther about a third farther away. Distances are estimates."
        ),
    ]
}

/// Plain values read from `FaceSettings`, checked against the allowed options.
public struct FaceSettingsValues: Equatable, Sendable {
    public let recognitionEnabled: Bool
    public let indeterminateLivenessPersonalizes: Bool
    public let lockDelay: TimeInterval
    public let nearDistance: FaceSettings.NearDistance
    public let matchStrictness: MatchStrictness

    /// Values outside the option lists fall back to the key's default.
    public init(
        recognitionEnabled: Bool = FaceSettings.recognitionEnabled.defaultValue,
        indeterminateLivenessPersonalizes: Bool = FaceSettings.indeterminateLivenessPersonalizes.defaultValue,
        lockDelaySeconds: Int = FaceSettings.lockDelaySeconds.defaultValue,
        nearDistance: String = FaceSettings.nearDistance.defaultValue,
        matchStrictness: String = FaceSettings.matchStrictness.defaultValue
    ) {
        self.matchStrictness = MatchStrictness(rawValue: matchStrictness) ?? .standard
        self.recognitionEnabled = recognitionEnabled
        self.indeterminateLivenessPersonalizes = indeterminateLivenessPersonalizes
        self.lockDelay = TimeInterval(
            FaceSettings.lockDelayOptions.contains(lockDelaySeconds) ? lockDelaySeconds : FaceSettings.lockDelaySeconds.defaultValue
        )
        self.nearDistance = FaceSettings.NearDistance(rawValue: nearDistance) ?? .standard
    }

    /// The engine configuration with these preferences applied on top of `base`.
    public func applied(to base: RecognitionEngineConfiguration) -> RecognitionEngineConfiguration {
        var configuration = base
        configuration.stabilizer.absenceTimeout = lockDelay
        configuration.stabilizer.matchTimeout = lockDelay
        configuration.liveness.indeterminateMayPersonalize = indeterminateLivenessPersonalizes
        configuration.proximity = nearDistance.policy
        configuration.matchPolicies = base.matchPolicies.adjusted(for: matchStrictness)
        return configuration
    }
}
