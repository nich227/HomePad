import Foundation
import HomePadCore

/// The faces the hub can rest on, in the order they are swiped through.
public enum FaceKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case modular
    case photos
    case weather
    case homeModular
    case calendar
    case flow
    case analog
    case fade
    case digital
    case homeCamera
    case rainbow

    public var id: String { rawValue }

    /// Faces that show nothing useful until a HomeKit home is available.
    public var needsHome: Bool {
        self == .homeModular || self == .homeCamera
    }
}

public enum FaceAccent: String, CaseIterable, Sendable {
    case white, profile, green, yellow, orange, red, purple, blue

    /// The rainbow tint to draw with, or nil for white. `profile` follows whoever is active and
    /// falls back to white for a guest.
    public func tint(profileTint: RainbowTint?) -> RainbowTint? {
        switch self {
        case .white: nil
        case .profile: profileTint
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .blue: .blue
        }
    }
}

public enum ClockFontStyle: String, CaseIterable, Sendable {
    case rounded, standard, serif, monospaced
}

public enum AnalogNumeralStyle: String, CaseIterable, Sendable {
    /// Four oversized numerals at twelve, three, six, and nine.
    case large
    case all
    case none

    public var hours: [Int] {
        switch self {
        case .large: [12, 3, 6, 9]
        case .all: Array(1...12)
        case .none: []
        }
    }
}

public enum AnalogDialColor: String, CaseIterable, Sendable {
    case green, yellow, orange, red, purple, blue, black

    public var tint: RainbowTint? {
        RainbowTint(rawValue: rawValue)
    }
}

public enum FadeDialColor: String, CaseIterable, Sendable {
    case gray, rose
}

public enum PhotosSource: String, CaseIterable, Sendable {
    case picked
    case sharedAlbum
}

public enum PhotosLayout: String, CaseIterable, Sendable {
    /// Digits sit between the background and the photo's subject.
    case depth
    /// Digits sit on top of the whole photo.
    case front
    /// A small time in the corner, like a framed photo.
    case corner
}

public enum CanvasMode: String, CaseIterable, Sendable {
    case square
    case fill
}

public enum HomeWallpaper: String, CaseIterable, Sendable {
    case face
    case black
}

/// Household-wide face options, already parsed from their stored strings.
public struct FaceOptions: Equatable, Sendable {
    public var enabledFaces: [FaceKind]
    public var digitalAccent: FaceAccent
    public var digitalFont: ClockFontStyle
    public var analogShowsTicks: Bool
    public var analogNumerals: AnalogNumeralStyle
    public var analogColor: AnalogDialColor
    public var fadeColor: FadeDialColor
    public var photosSource: PhotosSource
    public var photosLayout: PhotosLayout
    public var photosAlbumName: String
    public var photosShuffleMinutes: Int
    public var flowReactsToPresence: Bool

    public init(
        enabledFaces: [FaceKind] = FaceKind.allCases,
        digitalAccent: FaceAccent = .white,
        digitalFont: ClockFontStyle = .rounded,
        analogShowsTicks: Bool = false,
        analogNumerals: AnalogNumeralStyle = .large,
        analogColor: AnalogDialColor = .green,
        fadeColor: FadeDialColor = .gray,
        photosSource: PhotosSource = .picked,
        photosLayout: PhotosLayout = .depth,
        photosAlbumName: String = "",
        photosShuffleMinutes: Int = 5,
        flowReactsToPresence: Bool = true
    ) {
        self.enabledFaces = FacePager.normalized(enabledFaces)
        self.digitalAccent = digitalAccent
        self.digitalFont = digitalFont
        self.analogShowsTicks = analogShowsTicks
        self.analogNumerals = analogNumerals
        self.analogColor = analogColor
        self.fadeColor = fadeColor
        self.photosSource = photosSource
        self.photosLayout = photosLayout
        self.photosAlbumName = photosAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photosShuffleMinutes = max(1, photosShuffleMinutes)
        self.flowReactsToPresence = flowReactsToPresence
    }
}

public enum FacePager {
    /// Catalog order, no duplicates. The hub always has a face, so an empty list becomes Digital.
    public static func normalized(_ faces: [FaceKind]) -> [FaceKind] {
        let enabled = Set(faces)
        let ordered = FaceKind.allCases.filter(enabled.contains)
        return ordered.isEmpty ? [.digital] : ordered
    }

    /// The face to rest on: the one this person used last when it is still enabled.
    public static func initialFace(lastFace: FaceKind?, enabled: [FaceKind]) -> FaceKind {
        let faces = normalized(enabled)
        if let lastFace, faces.contains(lastFace) { return lastFace }
        return faces[0]
    }

    /// Steps through the faces and wraps at both ends, for arrow keys.
    public static func face(from current: FaceKind, step: Int, in enabled: [FaceKind]) -> FaceKind {
        let faces = normalized(enabled)
        guard let index = faces.firstIndex(of: current) else { return faces[0] }
        let count = faces.count
        return faces[((index + step) % count + count) % count]
    }
}

/// Which photo a rotating face shows at a given time. Deterministic so every redraw agrees.
public enum PhotoRotation {
    public static func index(count: Int, at date: Date, shuffleMinutes: Int) -> Int? {
        guard count > 0 else { return nil }
        let slot = Int(date.timeIntervalSinceReferenceDate / Double(max(1, shuffleMinutes) * 60))
        return ((slot % count) + count) % count
    }
}
