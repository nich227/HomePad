import Foundation
import HomePadBeamCore
import HomePadCore
import SwiftUI

extension View {
    /// On a companion, offers `urlText` to this person's other devices through Handoff while the
    /// view is on screen. Nothing is advertised unless the address passes the URL policy.
    public func beamHandoffAdvertising(urlText: String, title: String?, isEnabled: Bool) -> some View {
        let validated = try? BeamURLPolicy(allowsLocalHosts: false)
            .validate(BeamURLPolicy.normalizedUserInput(urlText)).get()
        return userActivity(HomePadIdentifiers.beamActivityType, isActive: isEnabled && validated != nil) { activity in
            guard let validated else { return }
            let payload = HandoffPayload(urlText: validated.url.absoluteString, title: title)
            activity.title = payload.title
            activity.webpageURL = validated.url
            activity.userInfo = payload.userInfo
            activity.requiredUserInfoKeys = [HandoffPayload.urlKey]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
            activity.isEligibleForPublicIndexing = false
            activity.isEligibleForPrediction = false
        }
    }

    /// On the hub, routes Handoff activities and `homepad://beam` links to the receiver.
    public func beamIncomingHandlers(_ receiver: BeamReceiver) -> some View {
        onContinueUserActivity(HomePadIdentifiers.beamActivityType) { receiver.handle(userActivity: $0) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { receiver.handle(userActivity: $0) }
            .onOpenURL { receiver.handle(url: $0) }
    }

    /// On a companion, routes `homepad://pair` links, which the Camera app opens after scanning
    /// a hub's pairing code, to the sender.
    public func beamPairingLinkHandler(_ sender: BeamSender) -> some View {
        onOpenURL { sender.handle(url: $0) }
    }
}
