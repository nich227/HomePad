import Foundation
import HomePadCore

/// Preferences for beaming. They are edited in the system Settings app; this package only reads.
public enum BeamSettings {
    public static let pane = "Beam"

    public static let receiveBeams = SettingKey<Bool>("beam.receiveBeams", default: true)
    public static let approvalMode = SettingKey<String>("beam.approvalMode", default: BeamApprovalMode.askFirst.rawValue)
    public static let hubName = SettingKey<String>("beam.hubName", default: "HomePad")
    public static let companionName = SettingKey<String>("beam.companionName", default: "iPhone")
    public static let sharePlayEnabled = SettingKey<Bool>("beam.sharePlay", default: true)
    public static let handoffEnabled = SettingKey<Bool>("beam.handoff", default: true)
    public static let keepHistory = SettingKey<Bool>("beam.keepHistory", default: true)
    public static let allowLocalAddresses = SettingKey<Bool>("beam.allowLocalAddresses", default: false)

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(
            receiveBeams,
            title: "Receive Beams",
            pane: pane,
            footer: "When on, paired iPhones can send pages to this hub while HomePad is on screen. Nothing is received until at least one iPhone is paired."
        ),
        SettingDescriptor(
            approvalMode,
            title: "When a Page Arrives",
            pane: pane,
            options: [
                .init(title: "Ask First", value: BeamApprovalMode.askFirst.rawValue),
                .init(title: "Open Immediately", value: BeamApprovalMode.openImmediately.rawValue),
            ],
            footer: "A page from a household member's iPhone is shown only to that person. It waits, unseen, until the hub recognizes them, then opens or asks as chosen here. The hub always asks for the first page from a newly paired iPhone, and for a page from an iPhone that belongs to nobody when the person in front is not recognized."
        ),
        SettingDescriptor(
            hubName,
            title: "Hub Name",
            pane: pane,
            footer: "Shown to paired iPhones and advertised on the local network. Do not use a name you would not want neighbors on the same network to see."
        ),
        SettingDescriptor(
            companionName,
            title: "This iPhone's Name",
            pane: pane,
            footer: "Shown on the hub next to pages you send."
        ),
        SettingDescriptor(sharePlayEnabled, title: "Browse Together with SharePlay", pane: pane),
        SettingDescriptor(
            handoffEnabled,
            title: "Handoff",
            pane: pane,
            footer: "On an iPhone, offers the page you are about to send to hubs signed in to the same Apple Account. On a hub, accepts those pages."
        ),
        SettingDescriptor(
            keepHistory,
            title: "Keep Recent Pages",
            pane: pane,
            footer: "Each person sees only their own recent pages. They are kept in memory only and are cleared when HomePad quits. A guest's are cleared when the guest leaves."
        ),
        SettingDescriptor(
            allowLocalAddresses,
            title: "Allow Local Network Addresses",
            pane: pane,
            footer: "When off, the hub refuses pages hosted on this network, such as a router's admin page."
        ),
    ]
}

/// A plain snapshot of the beam preferences. Pure logic takes this, never `HomePadSettings`.
public struct BeamPreferences: Equatable, Sendable {
    public var receiveBeams: Bool
    public var approvalMode: BeamApprovalMode
    public var hubName: String
    public var companionName: String
    public var sharePlayEnabled: Bool
    public var handoffEnabled: Bool
    public var keepHistory: Bool
    public var allowLocalAddresses: Bool

    public init(
        receiveBeams: Bool = BeamSettings.receiveBeams.defaultValue,
        approvalModeValue: String = BeamSettings.approvalMode.defaultValue,
        hubName: String = BeamSettings.hubName.defaultValue,
        companionName: String = BeamSettings.companionName.defaultValue,
        sharePlayEnabled: Bool = BeamSettings.sharePlayEnabled.defaultValue,
        handoffEnabled: Bool = BeamSettings.handoffEnabled.defaultValue,
        keepHistory: Bool = BeamSettings.keepHistory.defaultValue,
        allowLocalAddresses: Bool = BeamSettings.allowLocalAddresses.defaultValue
    ) {
        self.receiveBeams = receiveBeams
        self.approvalMode = BeamApprovalMode(settingValue: approvalModeValue)
        self.hubName = BeamText.sanitizedDeviceName(hubName, fallback: BeamSettings.hubName.defaultValue)
        self.companionName = BeamText.sanitizedDeviceName(companionName, fallback: BeamSettings.companionName.defaultValue)
        self.sharePlayEnabled = sharePlayEnabled
        self.handoffEnabled = handoffEnabled
        self.keepHistory = keepHistory
        self.allowLocalAddresses = allowLocalAddresses
    }

    public var urlPolicy: BeamURLPolicy {
        BeamURLPolicy(allowsLocalHosts: allowLocalAddresses)
    }

    @MainActor
    public static func read(from settings: HomePadSettings) -> BeamPreferences {
        BeamPreferences(
            receiveBeams: settings[BeamSettings.receiveBeams],
            approvalModeValue: settings[BeamSettings.approvalMode],
            hubName: settings[BeamSettings.hubName],
            companionName: settings[BeamSettings.companionName],
            sharePlayEnabled: settings[BeamSettings.sharePlayEnabled],
            handoffEnabled: settings[BeamSettings.handoffEnabled],
            keepHistory: settings[BeamSettings.keepHistory],
            allowLocalAddresses: settings[BeamSettings.allowLocalAddresses]
        )
    }
}
