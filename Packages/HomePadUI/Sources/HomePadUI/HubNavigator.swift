import Foundation
import HomePadUICore
import Observation

/// The app's handle on what the hub is showing. Create one, pass it to the root view, and call
/// it when something outside the shell needs the screen, for example an incoming beam.
@MainActor
@Observable
public final class HubNavigator {
    public private(set) var state = HubNavigationState()
    /// A recipe page waiting to be opened by the Recipes app.
    public private(set) var pendingRecipeURL: URL?

    public init() {}

    /// Covers the whole screen with the beam slot. Call when a page arrives from a companion.
    public func presentBeam() {
        state.presentTakeover()
    }

    public func dismissBeam() {
        state.dismissTakeover()
    }

    public func showFaces() {
        state.showFaces()
    }

    public func showHomeScreen() {
        state.showHomeScreen()
    }

    public func back() {
        state.back()
    }

    /// Opens an app if the person in front of the hub may see it.
    @discardableResult
    public func open(_ app: HubApp, context: AudienceContext) -> Bool {
        state.open(app, context: context)
    }

    /// Opens the recipe reader on a page, for example one beamed from an iPhone.
    public func openRecipe(_ url: URL, context: AudienceContext) {
        pendingRecipeURL = url
        state.open(.recipes, context: context)
    }

    func takePendingRecipeURL() -> URL? {
        defer { pendingRecipeURL = nil }
        return pendingRecipeURL
    }

    func audienceChanged(_ context: AudienceContext) {
        state.audienceChanged(context)
    }

    func restIfIdle(isSomeonePresent: Bool, idleSeconds: TimeInterval) {
        state.restIfIdle(isSomeonePresent: isSomeonePresent, idleSeconds: idleSeconds)
    }
}
