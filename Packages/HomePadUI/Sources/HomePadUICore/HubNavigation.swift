import Foundation

public enum HubSurface: Equatable, Sendable {
    /// The resting face.
    case faces
    /// The widget row and the grid of app icons.
    case homeScreen
    case app(HubApp)
}

/// A control that opens over whatever is showing, without leaving it.
public enum HubInlineControl: Equatable, Sendable {
    /// The dial for one thermostat.
    case thermostat(id: String)
    /// The brightness slider for one light.
    case dimmer(id: String)
    /// One camera, full screen.
    case camera(id: String)
}

/// Something that floats over the current surface. One at a time. A new kind, such as an
/// assistant or an incoming call, is a new case here and a line in `present(_:)`.
public enum HubOverlay: Equatable, Sendable {
    /// Night Mode, brightness, what is playing, timers, and who is using the hub.
    case controlCenter
    /// The faces as a row of live previews to choose from.
    case facePicker
    case inlineControl(HubInlineControl)
    /// The assistant another package supplies. It draws itself over everything.
    case assistant
}

/// What is in front of everything else on the hub. It names a kind of screen and never what
/// the screen contains.
public enum HubScreen: Equatable, Sendable {
    /// A face. Nil before the hub has settled on one.
    case face(FaceKind?)
    case homeScreen
    case app(HubApp)
    case overlay(HubOverlay)
    /// An incoming page covering the screen.
    case takeover
}

/// What a person or the hub itself can do to move between states.
public enum HubEvent: Equatable, Sendable {
    /// A press held on a face.
    case longPressCanvas
    /// A swipe up that starts at the bottom edge.
    case swipeUpFromBottomEdge
    /// A swipe down that starts at the top edge, away from its trailing corner.
    case swipeDown
    /// A swipe down that starts in the top trailing corner.
    case swipeDownFromTopTrailing
    /// A pull down from the middle of the top edge, or a tap on the assistant control, while an
    /// assistant is available.
    case openAssistant
    case tapApp(HubApp)
    case tapInlineControl(HubInlineControl)
    /// A face was chosen in the face picker.
    case chooseFace
    case dismissOverlay
    /// Nobody has touched the hub for this long. `timeout` is nil when the setting is Never.
    case idle(seconds: TimeInterval, isMediaPlaying: Bool, timeout: TimeInterval?)
}

/// Where the hub is: a face, the Home Screen, or an app; an optional overlay on top; and an
/// optional full-screen takeover for an incoming beam above everything. All transitions go
/// through here so audience rules are applied in one place.
public struct HubNavigationState: Equatable, Sendable {
    public private(set) var surface: HubSurface
    public private(set) var overlay: HubOverlay?
    public private(set) var isTakeoverPresented: Bool

    public init(surface: HubSurface = .faces, overlay: HubOverlay? = nil, isTakeoverPresented: Bool = false) {
        self.surface = surface
        self.overlay = overlay
        self.isTakeoverPresented = isTakeoverPresented
    }

    /// Swiping left or right changes the face only while a face is in front with nothing over it.
    public var canChangeFace: Bool {
        surface == .faces && overlay == nil && !isTakeoverPresented
    }

    /// Applies one event. Returns whether anything changed.
    @discardableResult
    public mutating func handle(_ event: HubEvent, context: AudienceContext) -> Bool {
        let before = self
        switch event {
        case .longPressCanvas:
            if canChangeFace {
                overlay = .facePicker
            }
        case .swipeUpFromBottomEdge:
            if isTakeoverPresented {
                isTakeoverPresented = false
            } else if overlay != nil {
                overlay = nil
            } else {
                surface = .homeScreen
            }
        case .swipeDown:
            if overlay == nil, !isTakeoverPresented, surface == .homeScreen {
                surface = .faces
            }
        case .swipeDownFromTopTrailing:
            present(.controlCenter)
        case .openAssistant:
            present(.assistant)
        case .tapApp(let app):
            open(app, context: context)
        case .tapInlineControl(let control):
            present(.inlineControl(control))
        case .chooseFace:
            if overlay == .facePicker {
                overlay = nil
            }
        case .dismissOverlay:
            overlay = nil
        case .idle(let seconds, let isMediaPlaying, let timeout):
            rest(idleSeconds: seconds, isMediaPlaying: isMediaPlaying, timeout: timeout)
        }
        return self != before
    }

    public mutating func showHomeScreen() {
        overlay = nil
        surface = .homeScreen
    }

    public mutating func showFaces() {
        overlay = nil
        surface = .faces
    }

    /// Overlay first, then app to Home Screen, then Home Screen to face. A takeover is
    /// dismissed before any of that.
    public mutating func back() {
        if isTakeoverPresented {
            isTakeoverPresented = false
            return
        }
        if overlay != nil {
            overlay = nil
            return
        }
        switch surface {
        case .app: surface = .homeScreen
        case .homeScreen, .faces: surface = .faces
        }
    }

    /// Opens the app when the audience may see it. Returns whether it opened.
    @discardableResult
    public mutating func open(_ app: HubApp, context: AudienceContext) -> Bool {
        guard VisibilityPolicy.canOpen(app, context: context) else { return false }
        overlay = nil
        surface = .app(app)
        return true
    }

    /// Brings the faces to the front for a request from outside the shell, such as the
    /// assistant. Returns false, and changes nothing, when the face is not one that is turned
    /// on. An open assistant stays open: it asked, and it closes itself.
    @discardableResult
    public mutating func showFace(_ kind: FaceKind, enabled: [FaceKind]) -> Bool {
        guard FacePager.normalized(enabled).contains(kind) else { return false }
        isTakeoverPresented = false
        if overlay != .assistant {
            overlay = nil
        }
        surface = .faces
        return true
    }

    /// What is in front, for telling something outside the shell what the hub shows.
    public func screen(face: FaceKind?) -> HubScreen {
        if isTakeoverPresented { return .takeover }
        if let overlay { return .overlay(overlay) }
        switch surface {
        case .faces: return .face(face)
        case .homeScreen: return .homeScreen
        case .app(let app): return .app(app)
        }
    }

    /// Shows an overlay over the current surface. The face picker belongs to the faces only.
    public mutating func present(_ overlay: HubOverlay) {
        guard !isTakeoverPresented else { return }
        if overlay == .facePicker, surface != .faces { return }
        self.overlay = overlay
    }

    public mutating func dismissOverlay() {
        overlay = nil
    }

    public mutating func presentTakeover() {
        isTakeoverPresented = true
    }

    public mutating func dismissTakeover() {
        isTakeoverPresented = false
    }

    /// Call when the person in front of the hub changes. An app the new audience may not see
    /// closes at once, so personal content never outlives the person it belongs to.
    public mutating func audienceChanged(_ context: AudienceContext) {
        if case .app(let app) = surface, !VisibilityPolicy.canOpen(app, context: context) {
            surface = .homeScreen
        }
    }

    /// Call when the audience signs out: a member's wait after the camera lost them ran out,
    /// another person took their place, someone switched profiles by hand, or the hub was
    /// locked. Nothing of theirs stays in front for whoever is next: a page that took over the
    /// screen closes, and the browser or a personal app gives way to the face. Losing sight of
    /// someone for a moment is not a sign out and must not be reported here.
    public mutating func audienceSignedOut() {
        isTakeoverPresented = false
        if case .app(let app) = surface, app == .beam || app.access == .personal {
            overlay = nil
            surface = .faces
        }
    }

    /// With no touch for the idle period, overlays close, the Home Screen returns to the face,
    /// and so does an app, unless something is playing. Two apps are read or watched without
    /// touching them and stay up: a recipe being cooked from, and the mirror.
    private mutating func rest(idleSeconds: TimeInterval, isMediaPlaying: Bool, timeout: TimeInterval?) {
        guard let timeout, idleSeconds >= timeout, !isTakeoverPresented else { return }
        overlay = nil
        switch surface {
        case .faces, .app(.recipes), .app(.mirror):
            return
        case .app:
            if !isMediaPlaying {
                surface = .faces
            }
        case .homeScreen:
            surface = .faces
        }
    }
}

/// Turns a drag into the event it means, from where it started and how far it went.
public enum HubGesture {
    /// The bottom edge that a swipe up must start in, as a fraction of the height.
    public static let bottomEdgeFraction = 0.12
    /// The top edge and the trailing part of the width that a control center swipe starts in.
    public static let topEdgeFraction = 0.16
    public static let trailingCornerFraction = 0.35
    /// The middle of the top edge, where a pull down opens the assistant: this fraction of the
    /// width on each side of the center.
    public static let topCenterFraction = 0.15
    /// A drag shorter than this is not a swipe.
    public static let threshold = 60.0

    /// `startX` and `startY` are in points from the top left of the area the hub draws in.
    /// Horizontal drags, and vertical drags that start away from the top and bottom edges,
    /// return nil: they belong to the face pager and to scrolling.
    public static func event(
        startX: Double,
        startY: Double,
        translationX: Double,
        translationY: Double,
        width: Double,
        height: Double,
        isAssistantAvailable: Bool = false
    ) -> HubEvent? {
        guard abs(translationY) > abs(translationX) * 1.5, abs(translationY) >= threshold else { return nil }
        if translationY < 0 {
            return startY >= height * (1 - bottomEdgeFraction) ? .swipeUpFromBottomEdge : nil
        }
        guard startY <= height * topEdgeFraction else { return nil }
        if startX >= width * (1 - trailingCornerFraction) {
            return .swipeDownFromTopTrailing
        }
        if isAssistantAvailable, abs(startX - width / 2) <= width * topCenterFraction {
            return .openAssistant
        }
        return .swipeDown
    }

    /// Whether a drag that starts here and goes down opens something over the screen: the
    /// control center from the top trailing corner, or the assistant from the top center. Such
    /// a drag must do only that, so whatever is under it does not also take it as a pull down.
    public static func startsOverlay(startX: Double, startY: Double, width: Double, height: Double, isAssistantAvailable: Bool) -> Bool {
        let event = event(startX: startX, startY: startY, translationX: 0, translationY: threshold, width: width, height: height, isAssistantAvailable: isAssistantAvailable)
        return event == .swipeDownFromTopTrailing || event == .openAssistant
    }
}

public struct CanvasFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Where the hub draws on the screen. Filling uses all of it. Square is the largest square that
/// fits, centered, with black around it.
public struct CanvasLayout: Equatable, Sendable {
    /// Corner radius of a square canvas as a fraction of its side. A filled screen has none.
    public static let cornerRadiusFraction = 0.1

    public let canvas: CanvasFrame
    /// True when the canvas does not reach the edges of the space, so it is drawn with rounded
    /// corners on black.
    public let isInset: Bool

    public init(width: Double, height: Double, mode: CanvasMode) {
        let availableWidth = max(0, width)
        let availableHeight = max(0, height)
        switch mode {
        case .fill:
            canvas = CanvasFrame(x: 0, y: 0, width: availableWidth, height: availableHeight)
            isInset = false
        case .square:
            let edge = min(availableWidth, availableHeight)
            canvas = CanvasFrame(x: (availableWidth - edge) / 2, y: (availableHeight - edge) / 2, width: edge, height: edge)
            isInset = availableWidth != availableHeight
        }
    }

    public var cornerRadius: Double {
        isInset ? min(canvas.width, canvas.height) * Self.cornerRadiusFraction : 0
    }
}

/// What the hub is showing, for the companion's status tab. Carries no personal content.
public struct HubStatusSummary: Codable, Equatable, Sendable {
    public static let channel = "hubSummary"
    /// A summary older than this is treated as "hub not reachable".
    public static let freshFor: TimeInterval = 120

    public var face: FaceKind
    public var showsHomeScreen: Bool
    public var app: HubApp?
    public var profileName: String?
    public var runningTimers: Int
    public var nextTimerEnd: Date?
    public var nowPlayingTitle: String?
    public var isNight: Bool
    public var updatedAt: Date

    public init(
        surface: HubSurface,
        face: FaceKind,
        profileName: String?,
        timers: [HubTimer],
        nowPlaying: NowPlaying?,
        isNight: Bool,
        at date: Date
    ) {
        self.face = face
        self.showsHomeScreen = surface == .homeScreen
        if case .app(let app) = surface { self.app = app } else { self.app = nil }
        self.profileName = profileName
        let ends = timers.compactMap { timer -> Date? in
            guard case .running(let endsAt) = timer.state else { return nil }
            return endsAt
        }
        self.runningTimers = ends.count
        self.nextTimerEnd = ends.min()
        self.nowPlayingTitle = (nowPlaying?.isPlaying ?? false) ? nowPlaying?.title : nil
        self.isNight = isNight
        self.updatedAt = date
    }

    public func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince(updatedAt) <= Self.freshFor
    }
}
