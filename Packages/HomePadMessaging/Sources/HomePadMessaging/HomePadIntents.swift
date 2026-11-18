import AppIntents
import Foundation
import HomePadMessagingCore

/// Where the App Intents find the running app. The app fills this in while it launches, before
/// any scene exists, because Shortcuts starts the app in the background to run an intent.
@MainActor
public final class HomePadIntentHandlers {
    public static let shared = HomePadIntentHandlers()

    /// Relays one incoming message. Set to `ProjectionHost.relayMessage(senderName:handle:text:)`.
    public var relayMessage: (@MainActor (_ senderName: String, _ handle: String?, _ text: String) async -> MessageRelayOutcome)?
    /// Sends a web page to a hub. Supplied by the app from its beaming feature.
    public var beam: (@MainActor (URL) async -> HubCommandOutcome)?
    /// Brings a projected app to the front on a hub. Set to `ProjectionHost.present(appID:)`.
    public var showApp: (@MainActor (_ appID: String) async -> HubCommandOutcome)?
    /// The apps this iPhone projects right now. Set to read `ProjectionHost.projectedApps`.
    public var projectedApps: (@MainActor () -> [ProjectedApp])?

    private init() {}

    /// Wires the three handlers a `ProjectionHost` can serve.
    public func register(host: ProjectionHost) {
        relayMessage = { [weak host] senderName, handle, text in
            await host?.relayMessage(senderName: senderName, handle: handle, text: text) ?? .unavailable
        }
        showApp = { [weak host] appID in
            await host?.present(appID: appID) ?? .unavailable
        }
        projectedApps = { [weak host] in
            host?.projectedApps ?? []
        }
    }
}

/// Makes this package's intents visible to the app. The app target lists it in the
/// `includedPackages` of its own `AppIntentsPackage`.
public struct HomePadMessagingIntents: AppIntentsPackage {}

// MARK: Relay a message

/// The action for a Shortcuts "When I get a message" automation. Shortcuts passes in who wrote
/// and what they wrote; this hands both to the running app, which shows them on a nearby hub.
public struct RelayMessageToHomePadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Relay Message to HomePad"
    public static let description = IntentDescription(
        "Shows a message you received on a nearby HomePad. Use it as the action of a Shortcuts automation that runs when you get a message.",
        categoryName: "Messages"
    )
    public static let supportedModes: IntentModes = .background
    // Messages arrive while the iPhone is locked. The hub still shows them only to their owner.
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Sender", description: "Who the message is from.")
    public var senderName: String

    @Parameter(title: "Message", description: "The text of the message.")
    public var message: String

    @Parameter(title: "Phone or Email", description: "Where a reply should go. Optional.")
    public var handle: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("Relay \(\.$message) from \(\.$senderName) to HomePad") {
            \.$handle
        }
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let outcome = await HomePadIntentHandlers.shared.relayMessage?(senderName, handle, message) ?? .unavailable
        return .result(value: outcome.wasDelivered, dialog: IntentDialog(stringLiteral: Self.text(for: outcome)))
    }

    static func text(for outcome: MessageRelayOutcome) -> String {
        switch outcome {
        case .delivered:
            String(localized: "Sent to HomePad.")
        case .keptForLater:
            String(localized: "No HomePad is nearby. The message will show when one connects while HomePad stays open on this iPhone.")
        case .duplicate:
            String(localized: "This message was already relayed.")
        case .disabled:
            String(localized: "Showing Messages on HomePad is turned off in Settings.")
        case .rejected(.emptySender):
            String(localized: "The sender is missing. Pass the sender from the automation.")
        case .rejected(.emptyBody):
            String(localized: "The message is empty. Pass the message content from the automation.")
        case .unavailable:
            String(localized: "HomePad is not ready. Open HomePad on this iPhone once, then try again.")
        }
    }
}

// MARK: Beam a page

public struct BeamToHomePadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Beam to HomePad"
    public static let description = IntentDescription("Shows a web page on a nearby HomePad.", categoryName: "Beam")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Page", description: "The web address to show.")
    public var url: URL

    public static var parameterSummary: some ParameterSummary {
        Summary("Beam \(\.$url) to HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let outcome: HubCommandOutcome
        if let page = try? MessageDeepLinkCodec.validatedPage(url.absoluteString) {
            outcome = await HomePadIntentHandlers.shared.beam?(page) ?? .unavailable
        } else {
            outcome = .rejected
        }
        let text = switch outcome {
        case .delivered: String(localized: "Sent to HomePad.")
        case .noHubReachable: String(localized: "No HomePad is nearby.")
        case .rejected: String(localized: "Only web pages that start with http or https can be sent to HomePad.")
        case .unavailable: String(localized: "HomePad is not ready. Open HomePad on this iPhone once, then try again.")
        }
        return .result(value: outcome.wasDelivered, dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: Show an app

/// One of this iPhone's projected apps, as a choice in Shortcuts and Siri.
public struct ProjectedAppEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "HomePad App"
    public static let defaultQuery = ProjectedAppQuery()

    public let id: String
    public let name: String
    public let symbolName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }

    init(_ app: ProjectedApp) {
        id = app.id
        name = app.name
        symbolName = app.symbolName
    }
}

public struct ProjectedAppQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [ProjectedAppEntity] {
        available().filter { identifiers.contains($0.id) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [ProjectedAppEntity] {
        available()
    }

    @MainActor
    private func available() -> [ProjectedAppEntity] {
        (HomePadIntentHandlers.shared.projectedApps?() ?? []).map(ProjectedAppEntity.init)
    }
}

public struct ShowOnHomePadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show on HomePad"
    public static let description = IntentDescription("Brings one of this iPhone's apps to the front on a nearby HomePad.", categoryName: "Projection")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "App")
    public var app: ProjectedAppEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$app) on HomePad")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let outcome = await HomePadIntentHandlers.shared.showApp?(app.id) ?? .unavailable
        let text = switch outcome {
        case .delivered: String(localized: "Showing \(app.name) on HomePad.")
        case .noHubReachable: String(localized: "No HomePad is nearby.")
        case .rejected: String(localized: "\(app.name) is not shown on HomePad. Check HomePad in Settings.")
        case .unavailable: String(localized: "HomePad is not ready. Open HomePad on this iPhone once, then try again.")
        }
        return .result(value: outcome.wasDelivered, dialog: IntentDialog(stringLiteral: text))
    }
}
