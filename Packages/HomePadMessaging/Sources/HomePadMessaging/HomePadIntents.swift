import AppIntents
import Foundation
import HomePadMessagingCore

/// Where the App Intents find the running app. The app fills this in while it launches, before
/// any scene exists, because Shortcuts starts the app in the background to run an intent.
@MainActor
public final class HomePadIntentHandlers {
    public static let shared = HomePadIntentHandlers()

    /// Sends a web page to a hub. Supplied by the app from its beaming feature.
    public var beam: (@MainActor (URL) async -> HubCommandOutcome)?
    /// Brings a projected app to the front on a hub. Set to `ProjectionHost.present(appID:)`.
    public var showApp: (@MainActor (_ appID: String) async -> HubCommandOutcome)?
    /// The apps this iPhone projects right now. Set to read `ProjectionHost.projectedApps`.
    public var projectedApps: (@MainActor () -> [ProjectedApp])?

    private init() {}

    /// Wires the two handlers a `ProjectionHost` can serve.
    public func register(host: ProjectionHost) {
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
