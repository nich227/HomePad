import Foundation
import HomePadBeamCore
import HomePadCore
import SwiftUI
import UIKit

/// Builds the pieces every beam screen shares for one process: the store, this device's identity,
/// and the peer link.
public enum BeamEnvironment {
    /// The link for this device. The device ID is created on first use and kept in the Keychain,
    /// so the app and its share extension present the same identity to a hub.
    @MainActor
    public static func makePeerLink(
        role: DeviceRole,
        settings: HomePadSettings,
        store: any PairingStore = KeychainPairingStore()
    ) throws(PairingStoreError) -> PeerLink {
        let preferences = BeamPreferences.read(from: settings)
        let id = try store.loadOrCreateLocalDeviceID()
        let name = role == .hub ? preferences.hubName : preferences.companionName
        return PeerLink(localDevice: PeerDevice(id: id, name: name, role: role), store: store)
    }
}

extension BeamURLRejection {
    var message: String {
        switch self {
        case .empty: String(localized: "Enter a web address.")
        case .tooLong: String(localized: "That address is too long.")
        case .malformed: String(localized: "That does not look like a web address.")
        case .unsupportedScheme: String(localized: "Only http and https pages can be sent.")
        case .missingHost: String(localized: "The address is missing a site name.")
        case .embeddedCredentials: String(localized: "Addresses that contain a user name or password cannot be sent.")
        case .localHost: String(localized: "Pages on the local network are turned off for this hub.")
        }
    }
}

extension BeamOutcome {
    var message: String {
        switch self {
        case .opened: String(localized: "Opened on the hub.")
        case .awaitingApproval: String(localized: "Sent. Waiting for someone at the hub to open it.")
        case .declined: String(localized: "Someone at the hub declined the page.")
        case .rateLimited: String(localized: "Too many pages sent at once. Try again in a moment.")
        case .rejected(let reason): reason.message
        case .unknown: String(localized: "The hub answered in a way this version does not understand.")
        }
    }
}

extension BeamSendError {
    var message: String {
        switch self {
        case .invalidURL(let reason): reason.message
        case .noPairedHub: String(localized: "Pair this iPhone with a hub first.")
        case .hubUnreachable: String(localized: "The hub could not be reached. Make sure HomePad is open on it and both devices are on the same network.")
        case .noReceipt: String(localized: "The page was sent, but the hub did not confirm it.")
        }
    }
}

/// Opens this app's page in the Settings app, where every beam preference lives.
struct OpenSettingsButton: View {
    let title: LocalizedStringKey
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(title, systemImage: "gear") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
        }
        .accessibilityHint(Text("Opens HomePad in the Settings app"))
    }
}
