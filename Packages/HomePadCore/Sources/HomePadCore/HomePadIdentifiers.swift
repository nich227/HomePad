import Foundation

/// Identifiers shared by the app, its extensions, and the feature packages. The bundle prefix
/// here must match `HOMEPAD_BUNDLE_PREFIX` in `Config/Shared.xcconfig`.
public enum HomePadIdentifiers {
    public static let bundlePrefix = "com.kevster.HomePad"
    public static let appGroup = "group.com.kevster.HomePad"
    public static let keychainService = "com.kevster.HomePad"
    public static let urlScheme = "homepad"
    public static let bonjourServiceType = "_homepad._tcp"
    public static let beamActivityType = "com.kevster.HomePad.beam"
    public static let sharePlayActivityIdentifier = "com.kevster.HomePad.beam-together"
}
