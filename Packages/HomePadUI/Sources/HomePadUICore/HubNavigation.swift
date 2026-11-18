import Foundation

public enum HubSurface: Equatable, Sendable {
    /// The resting face.
    case faces
    /// The app view with icons and widgets.
    case homeScreen
    case app(HubApp)
}

/// Where the hub is: face, Home Screen, or an app, plus an optional full-screen takeover for an
/// incoming beam. All transitions go through here so audience rules are applied in one place.
public struct HubNavigationState: Equatable, Sendable {
    public private(set) var surface: HubSurface
    public private(set) var isTakeoverPresented: Bool

    public init(surface: HubSurface = .faces, isTakeoverPresented: Bool = false) {
        self.surface = surface
        self.isTakeoverPresented = isTakeoverPresented
    }

    public mutating func showHomeScreen() {
        surface = .homeScreen
    }

    public mutating func showFaces() {
        surface = .faces
    }

    /// App to Home Screen, Home Screen to face. A takeover is dismissed first.
    public mutating func back() {
        if isTakeoverPresented {
            isTakeoverPresented = false
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
        surface = .app(app)
        return true
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

    /// The hub drifts back to its face once nobody has been there for a while. Apps someone is
    /// likely still using from across the room stay up.
    public mutating func restIfIdle(isSomeonePresent: Bool, idleSeconds: TimeInterval, timeout: TimeInterval = 90) {
        guard !isSomeonePresent, idleSeconds >= timeout, !isTakeoverPresented else { return }
        switch surface {
        case .app(.recipes), .app(.music), .app(.timers), .app(.mirror), .faces:
            return
        case .app, .homeScreen:
            surface = .faces
        }
    }
}

public enum SwipeAction: Equatable, Sendable {
    case up, down
}

public enum SwipeDecision {
    /// A mostly vertical drag past the threshold. Horizontal drags belong to the face pager.
    public static func vertical(translationX: Double, translationY: Double, threshold: Double = 60) -> SwipeAction? {
        guard abs(translationY) > abs(translationX) * 1.5, abs(translationY) >= threshold else { return nil }
        return translationY < 0 ? .up : .down
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

/// Where the square hub canvas sits on a screen that is not square, and where the optional second
/// column goes.
public struct CanvasLayout: Equatable, Sendable {
    /// Corner radius of the square canvas as a fraction of its side.
    public static let cornerRadiusFraction = 0.1
    /// The second column is only worth showing when it is at least this fraction of the square.
    public static let minimumSideFraction = 0.28

    public let square: CanvasFrame
    public let side: CanvasFrame?

    public init(width: Double, height: Double, mode: CanvasMode, margin: Double = 0, gap: Double = 0) {
        let availableWidth = max(0, width - 2 * margin)
        let availableHeight = max(0, height - 2 * margin)
        let edge = min(availableWidth, availableHeight)
        let leftoverWidth = availableWidth - edge - gap
        let leftoverHeight = availableHeight - edge - gap
        if mode == .fill, leftoverWidth >= edge * Self.minimumSideFraction {
            square = CanvasFrame(x: margin, y: margin + (availableHeight - edge) / 2, width: edge, height: edge)
            side = CanvasFrame(x: margin + edge + gap, y: margin, width: leftoverWidth, height: availableHeight)
        } else if mode == .fill, leftoverHeight >= edge * Self.minimumSideFraction {
            square = CanvasFrame(x: margin + (availableWidth - edge) / 2, y: margin, width: edge, height: edge)
            side = CanvasFrame(x: margin, y: margin + edge + gap, width: availableWidth, height: leftoverHeight)
        } else {
            square = CanvasFrame(
                x: margin + (availableWidth - edge) / 2,
                y: margin + (availableHeight - edge) / 2,
                width: edge,
                height: edge
            )
            side = nil
        }
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
