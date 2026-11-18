import Foundation

public enum HomeAccessoryKind: String, Sendable, CaseIterable {
    case light, outlet, fan, lock, other

    public var symbolName: String {
        switch self {
        case .light: "lightbulb.fill"
        case .outlet: "poweroutlet.type.b.fill"
        case .fan: "fan.fill"
        case .lock: "lock.fill"
        case .other: "switch.2"
        }
    }
}

public struct HomeAccessory: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var roomName: String
    public var kind: HomeAccessoryKind
    /// On for lights and switches, locked for locks.
    public var isOn: Bool
    /// 0...100, nil when the accessory cannot dim.
    public var brightness: Int?
    public var isReachable: Bool

    public init(id: String, name: String, roomName: String, kind: HomeAccessoryKind, isOn: Bool, brightness: Int? = nil, isReachable: Bool = true) {
        self.id = id
        self.name = name
        self.roomName = roomName
        self.kind = kind
        self.isOn = isOn
        self.brightness = brightness
        self.isReachable = isReachable
    }
}

public struct HomeScene: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// A glyph guessed from common scene names.
    public var symbolName: String {
        let lowered = name.lowercased()
        if lowered.contains("morning") { return "sun.max.fill" }
        if lowered.contains("night") || lowered.contains("sleep") { return "moon.fill" }
        if lowered.contains("arrive") || lowered.contains("home") { return "figure.walk.arrival" }
        if lowered.contains("leave") || lowered.contains("away") { return "figure.walk.departure" }
        return "sparkles"
    }
}

public struct HomeThermostat: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var roomName: String
    public var currentCelsius: Double
    public var targetCelsius: Double

    public init(id: String, name: String, roomName: String, currentCelsius: Double, targetCelsius: Double) {
        self.id = id
        self.name = name
        self.roomName = roomName
        self.currentCelsius = currentCelsius
        self.targetCelsius = targetCelsius
    }
}

public struct HomeCamera: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var roomName: String

    public init(id: String, name: String, roomName: String) {
        self.id = id
        self.name = name
        self.roomName = roomName
    }
}

public enum HomeAccess: Equatable, Sendable {
    case unknown
    case denied
    case noHomes
    case ready
}

/// Everything the hub shows about the home, copied out of the home framework into values.
public struct HomeSnapshot: Equatable, Sendable {
    public var homeName: String
    public var accessories: [HomeAccessory]
    public var scenes: [HomeScene]
    public var thermostats: [HomeThermostat]
    public var cameras: [HomeCamera]

    public init(homeName: String = "", accessories: [HomeAccessory] = [], scenes: [HomeScene] = [], thermostats: [HomeThermostat] = [], cameras: [HomeCamera] = []) {
        self.homeName = homeName
        self.accessories = accessories
        self.scenes = scenes
        self.thermostats = thermostats
        self.cameras = cameras
    }

    public static let empty = HomeSnapshot()

    /// Room names in first-seen order, for the room sections of the Home app.
    public var roomNames: [String] {
        var seen = Set<String>()
        return accessories.map(\.roomName).filter { seen.insert($0).inserted }
    }

    public func accessories(inRoom room: String) -> [HomeAccessory] {
        accessories.filter { $0.roomName == room }
    }
}

/// One small tile of the Home Modular face or the Home app grid.
public enum HomeTile: Identifiable, Equatable, Sendable {
    case accessory(HomeAccessory)
    case scene(HomeScene)
    case camera(HomeCamera)

    public var id: String {
        switch self {
        case .accessory(let accessory): "accessory.\(accessory.id)"
        case .scene(let scene): "scene.\(scene.id)"
        case .camera(let camera): "camera.\(camera.id)"
        }
    }
}

public enum HomeFavorites {
    /// The Home Modular face has one large thermostat tile and five small ones. Small tiles are a
    /// camera when there is one, then scenes, then accessories that are reachable.
    public static func smallTiles(in snapshot: HomeSnapshot, limit: Int = 5) -> [HomeTile] {
        var tiles: [HomeTile] = []
        if let camera = snapshot.cameras.first {
            tiles.append(.camera(camera))
        }
        tiles += snapshot.scenes.prefix(2).map(HomeTile.scene)
        tiles += snapshot.accessories.filter(\.isReachable).map(HomeTile.accessory)
        return Array(tiles.prefix(max(0, limit)))
    }
}

public enum HomeControlPolicy {
    /// Anyone at the hub may switch lights and lock a door. Unlocking a door needs a household
    /// member, so a visitor cannot open the house from the shared screen.
    public static func mayOperate(_ accessory: HomeAccessory, turningOn: Bool, isGuest: Bool) -> Bool {
        let isUnlocking = accessory.kind == .lock && !turningOn
        return !(isUnlocking && isGuest)
    }
}

public enum ThermostatMath {
    public static let celsiusRange: ClosedRange<Double> = 10...32

    /// One press of the up or down chevron: one degree in the displayed unit.
    public static func stepped(targetCelsius: Double, direction: Int, unit: TemperatureUnit) -> Double {
        let delta = unit == .fahrenheit ? 5.0 / 9.0 : 1.0
        let moved = targetCelsius + delta * Double(direction.signum())
        return min(max(moved, celsiusRange.lowerBound), celsiusRange.upperBound)
    }
}

public enum BrightnessMath {
    /// A light set to zero brightness is off; anything else is on at that level.
    public static func normalized(_ value: Double) -> (brightness: Int, isOn: Bool) {
        let clamped = Int(min(max(value.isFinite ? value : 0, 0), 100).rounded())
        return (clamped, clamped > 0)
    }
}

public enum CameraGrid {
    public static let limit = 9

    /// Rows and columns for up to nine camera tiles.
    public static func dimensions(count: Int) -> (columns: Int, rows: Int) {
        let shown = min(max(count, 0), limit)
        switch shown {
        case 0, 1: return (1, 1)
        case 2: return (2, 1)
        case 3, 4: return (2, 2)
        case 5, 6: return (3, 2)
        default: return (3, 3)
        }
    }
}
