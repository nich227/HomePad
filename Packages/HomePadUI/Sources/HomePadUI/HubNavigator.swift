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
    /// True while Do Not Disturb is on in the control center. The app holds its own banners
    /// back while it is; the hub silences its timer and alarm sounds itself.
    public internal(set) var isDoNotDisturbOn = false

    /// True while the hub is in Night Mode, however it got there: the schedule, the room
    /// light, the control center's switch, or `setNightMode`.
    public private(set) var isNightMode = false
    /// The faces that are turned on in Settings, in the order the hub shows them. Empty until
    /// the hub is on screen.
    public private(set) var enabledFaces: [FaceKind] = []
    /// The face the hub is resting on, or would return to.
    public private(set) var currentFace: FaceKind?
    /// Requests from outside that the hub's view carries out when it sees them.
    private(set) var nightRequest: NightRequest?
    private(set) var faceRequest: FaceRequest?
    @ObservationIgnored private var requestCount = 0

    struct NightRequest: Equatable {
        let isOn: Bool
        let serial: Int
    }

    struct FaceRequest: Equatable {
        let kind: FaceKind
        let serial: Int
    }

    public init() {}

    /// The name, in the person's language, of what is in front: a face's name, an app's name,
    /// "Home Screen", "Control Center". It never includes anything personal.
    public var screenTitle: String {
        state.screen(face: currentFace).title
    }

    /// Turns Night Mode on or off as the control center's switch does: for now, until the next
    /// start or end hour of the night schedule, and never as a stored preference. Asking for
    /// what the hub already shows changes nothing. `isNightMode` follows once the hub has
    /// carried it out, which it does while it is on screen.
    public func setNightMode(_ isOn: Bool) {
        requestCount += 1
        nightRequest = NightRequest(isOn: isOn, serial: requestCount)
    }

    /// Brings the faces to the front on the given face. Returns false, and changes nothing,
    /// when that face is not turned on in Settings or the hub is not on screen yet. An open
    /// assistant stays open over the face.
    @discardableResult
    public func showFace(_ kind: FaceKind) -> Bool {
        guard !enabledFaces.isEmpty, state.showFace(kind, enabled: enabledFaces) else { return false }
        requestCount += 1
        faceRequest = FaceRequest(kind: kind, serial: requestCount)
        currentFace = kind
        return true
    }

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

    /// The hub's view reports its night state, so `isNightMode` is what is on screen.
    func nightChanged(_ isNight: Bool) {
        if isNightMode != isNight {
            isNightMode = isNight
        }
    }

    /// The hub's view reports which faces are on and which one is in front.
    func facesChanged(enabled: [FaceKind], current: FaceKind?) {
        if enabledFaces != enabled {
            enabledFaces = enabled
        }
        if currentFace != current {
            currentFace = current
        }
    }

    func audienceSignedOut() {
        state.audienceSignedOut()
    }

    func audienceChanged(_ context: AudienceContext) {
        state.audienceChanged(context)
    }

    /// Applies a gesture, a tap, or the idle timer through the hub's state machine. Returns
    /// whether anything changed.
    @discardableResult
    public func handle(_ event: HubEvent, context: AudienceContext) -> Bool {
        state.handle(event, context: context)
    }

    /// Shows an overlay over whatever is in front, for example the assistant.
    public func present(_ overlay: HubOverlay) {
        state.present(overlay)
    }

    public func dismissOverlay() {
        state.dismissOverlay()
    }
}
