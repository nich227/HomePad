import HomePadBeamCore
import HomePadCore
import HomePadFaceCore
import HomePadKioskCore
import HomePadMessagingCore
import HomePadUICore

/// Every preference the app reads, in the order the Settings app shows them. The app registers
/// these defaults at launch, and `homepad-settings` writes `Settings.bundle` from the same list.
public enum SettingsCatalog {
    public static let rootPane = GeneralSettings.pane

    public static let descriptors: [SettingDescriptor] =
        GeneralSettings.descriptors
        + KioskSettings.descriptors
        + FaceSettings.descriptors
        + BeamSettings.descriptors
        + MessagingSettings.descriptors
        + UISettings.descriptors

    /// Preferences that extensions read. The app copies their values into the app group's
    /// defaults, because an extension cannot see the app's own defaults.
    public static let sharedWithExtensions: [String] = [
        BeamSettings.companionName.name,
        MessagingSettings.suggestRecentPages.name,
    ]
}
