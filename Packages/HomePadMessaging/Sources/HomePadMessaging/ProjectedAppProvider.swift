import Foundation
import HomePadMessagingCore

/// How a provider wants the app's navigation stack to change after an action.
public enum ProjectionNavigation: Sendable, Equatable {
    case none
    case push(templateID: String)
    /// Show one detail screen above the root, replacing any detail already showing.
    case showDetail(templateID: String)
    case pop
}

/// A built-in or app-supplied projected app. The provider owns its data and describes it with
/// templates; `ProjectionHost` owns navigation and the link to the hub.
///
/// To add an app: implement this protocol, give it a unique `app.id`, build its screens from
/// `ProjectionTemplate` cases, and pass it to `ProjectionHost.init(channel:settings:providers:)`.
@MainActor
public protocol ProjectedAppProvider: AnyObject {
    var app: ProjectedApp { get }
    var rootTemplateID: String { get }

    /// Start observing data. Call `onChange` whenever a template may have changed; the host then
    /// asks for fresh templates and sends only the ones that differ.
    func activate(onChange: @escaping @MainActor () -> Void) async
    func deactivate()

    /// The current content of a template, or `nil` when that screen no longer exists.
    func template(id: String) async -> ProjectionTemplate?

    func handle(actionID: String, payload: [String: String]) async -> ProjectionNavigation
    func handle(mediaCommand: MediaCommand)
    /// The hub brought the app to the front.
    func launched() async
}

extension ProjectedAppProvider {
    public func handle(mediaCommand: MediaCommand) {}
    public func launched() async {}
}

/// Shown for an app that cannot produce its root screen.
func placeholderTemplate(id: String, title: String, message: String, limits: ProjectionLimits = .standard) -> ProjectionTemplate {
    .information(
        InformationTemplate(
            id: id,
            title: title.projectionTruncated(to: limits.maxTitleLength),
            items: [
                InformationItem(
                    id: "status",
                    label: String(localized: "Status"),
                    value: message.projectionTruncated(to: limits.maxSubtitleLength)
                ),
            ]
        )
    )
}
