import CoreTransferable
import Foundation
import GroupActivities
import HomePadBeamCore
import HomePadCore

/// Browsing one page together. Everyone in the session sees the same address; navigation is kept
/// in step with messages, not by sharing the screen.
public struct BeamTogetherActivity: GroupActivity, Sendable {
    public static let activityIdentifier = HomePadIdentifiers.sharePlayActivityIdentifier

    public let url: URL
    public let title: String?

    public init(url: ValidatedURL, title: String?) {
        self.url = url.url
        self.title = BeamText.sanitizedTitle(title)
    }

    public var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = title ?? String(localized: "Browse Together")
        metadata.subtitle = url.host()
        metadata.fallbackURL = url
        metadata.supportsContinuationOnTV = false
        return metadata
    }
}

/// Lets a `ShareLink` carry the activity, which is how the system finds something to offer when
/// two iPhones are brought together.
extension BeamTogetherActivity: Transferable {}
