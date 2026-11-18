import Foundation

/// Whose layout this is. Everyone who is not recognized shares the guest layout.
public enum LayoutOwner: Hashable, Sendable {
    case guest
    case profile(UUID)

    public var storageKey: String {
        switch self {
        case .guest: "guest"
        case .profile(let id): id.uuidString.lowercased()
        }
    }
}

public enum HomeScreenItem: Hashable, Sendable, Identifiable {
    case app(HubApp)
    case widget(HubWidgetKind)

    public var id: String {
        switch self {
        case .app(let app): "app.\(app.rawValue)"
        case .widget(let widget): "widget.\(widget.rawValue)"
        }
    }

    public init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "app":
            guard let app = HubApp(rawValue: parts[1]) else { return nil }
            self = .app(app)
        case "widget":
            guard let widget = HubWidgetKind(rawValue: parts[1]) else { return nil }
            self = .widget(widget)
        default:
            return nil
        }
    }

    public var access: ContentAccess {
        switch self {
        case .app(let app): app.access
        case .widget(let widget): widget.access
        }
    }

    /// Grid cells per side. Widgets are two by two, icons one by one.
    public var span: Int {
        switch self {
        case .app: 1
        case .widget: 2
        }
    }
}

/// One person's Home Screen: the order of icons and widgets, and the face they used last.
public struct HomeScreenLayout: Equatable, Sendable {
    public static let currentVersion = 1

    public var lastFace: FaceKind?
    public var items: [HomeScreenItem]

    public init(lastFace: FaceKind? = nil, items: [HomeScreenItem]) {
        self.lastFace = lastFace
        self.items = items
    }

    public static func defaultLayout(for owner: LayoutOwner) -> HomeScreenLayout {
        let items: [HomeScreenItem] = [
            .app(.messages), .app(.beam), .widget(.weather),
            .app(.home), .app(.music),
            .widget(.timers), .app(.timers), .app(.alarms),
            .app(.recipes), .app(.clock),
            .app(.photos), .app(.mirror), .widget(.nowPlaying),
            .app(.weather), .app(.projectedApps),
            .widget(.home), .widget(.messages),
            .app(.people), .app(.pairing), .app(.settings),
        ]
        return HomeScreenLayout(items: items).sanitized(for: owner)
    }

    /// Drops duplicates and anything this owner can never see, and appends catalog apps the saved
    /// layout predates so a new app is not lost behind an old file.
    public func sanitized(for owner: LayoutOwner) -> HomeScreenLayout {
        var seen = Set<HomeScreenItem>()
        var result: [HomeScreenItem] = []
        for item in items + HubApp.allCases.map(HomeScreenItem.app) where seen.insert(item).inserted {
            if owner == .guest, item.access == .member || item.access == .personal { continue }
            result.append(item)
        }
        return HomeScreenLayout(lastFace: lastFace, items: result)
    }

    /// Moves `itemID` so it sits where `targetID` is. Unknown ids leave the layout unchanged.
    public mutating func move(itemID: String, onto targetID: String) {
        guard itemID != targetID,
              let from = items.firstIndex(where: { $0.id == itemID }),
              let to = items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
    }
}

extension HomeScreenLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case lastFace, items
    }

    /// Unknown faces and items are dropped instead of failing the whole file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let face = try container.decodeIfPresent(String.self, forKey: .lastFace)
        let ids = try container.decode([String].self, forKey: .items)
        self.init(lastFace: face.flatMap(FaceKind.init(rawValue:)), items: ids.compactMap(HomeScreenItem.init(id:)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastFace?.rawValue, forKey: .lastFace)
        try container.encode(items.map(\.id), forKey: .items)
    }
}

public enum LayoutCodec {
    private static let codec = VersionedCodec<HomeScreenLayout>(version: HomeScreenLayout.currentVersion)

    public static func encode(_ layout: HomeScreenLayout) throws -> Data {
        try codec.encode(layout)
    }

    /// A file from an unknown schema version, or one that does not parse, becomes the default
    /// layout. A Home Screen is cheap to rebuild and must never block the hub from starting.
    public static func decode(_ data: Data?, owner: LayoutOwner) -> HomeScreenLayout {
        guard let data, let layout = try? codec.decode(data) else { return .defaultLayout(for: owner) }
        return layout.sanitized(for: owner)
    }
}

public protocol LayoutStore: Sendable {
    func layout(for owner: LayoutOwner) -> HomeScreenLayout
    func save(_ layout: HomeScreenLayout, for owner: LayoutOwner) throws(SnapshotStoreError)
    func removeLayout(for owner: LayoutOwner) throws(SnapshotStoreError)
}

/// One JSON file per owner inside `directory`.
public struct FileLayoutStore: LayoutStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func layout(for owner: LayoutOwner) -> HomeScreenLayout {
        LayoutCodec.decode(try? file(for: owner).load(), owner: owner)
    }

    public func save(_ layout: HomeScreenLayout, for owner: LayoutOwner) throws(SnapshotStoreError) {
        guard let data = try? LayoutCodec.encode(layout.sanitized(for: owner)) else { throw .unwritable }
        try file(for: owner).save(data)
    }

    public func removeLayout(for owner: LayoutOwner) throws(SnapshotStoreError) {
        try file(for: owner).remove()
    }

    private func file(for owner: LayoutOwner) -> FileSnapshotStore {
        FileSnapshotStore(url: directory.appendingPathComponent("\(owner.storageKey).json"))
    }
}

public final class InMemoryLayoutStore: LayoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private var layouts: [LayoutOwner: HomeScreenLayout]

    public init(layouts: [LayoutOwner: HomeScreenLayout] = [:]) {
        self.layouts = layouts
    }

    public func layout(for owner: LayoutOwner) -> HomeScreenLayout {
        lock.withLock { layouts[owner]?.sanitized(for: owner) ?? .defaultLayout(for: owner) }
    }

    public func save(_ layout: HomeScreenLayout, for owner: LayoutOwner) throws(SnapshotStoreError) {
        lock.withLock { layouts[owner] = layout.sanitized(for: owner) }
    }

    public func removeLayout(for owner: LayoutOwner) throws(SnapshotStoreError) {
        lock.withLock { layouts[owner] = nil }
    }
}

/// Places icons and two by two widgets on the Home Screen grid.
public enum HomeGridPacker {
    public struct Placement: Equatable, Sendable, Identifiable {
        public let item: HomeScreenItem
        public let column: Int
        public let row: Int
        public let span: Int

        public var id: String { item.id }
    }

    public struct Result: Equatable, Sendable {
        public let placements: [Placement]
        public let rowCount: Int
    }

    /// First fit, scanning rows top to bottom, so a widget never leaves a hole an icon could fill.
    public static func pack(_ items: [HomeScreenItem], columns: Int) -> Result {
        let columns = max(2, columns)
        var occupied = Set<Int>()
        var placements: [Placement] = []
        var rowCount = 0
        for item in items {
            let span = min(item.span, columns)
            var slot = 0
            while !fits(slot: slot, span: span, columns: columns, occupied: occupied) {
                slot += 1
            }
            let row = slot / columns
            let column = slot % columns
            for dy in 0..<span {
                for dx in 0..<span {
                    occupied.insert((row + dy) * columns + column + dx)
                }
            }
            placements.append(Placement(item: item, column: column, row: row, span: span))
            rowCount = max(rowCount, row + span)
        }
        return Result(placements: placements, rowCount: rowCount)
    }

    private static func fits(slot: Int, span: Int, columns: Int, occupied: Set<Int>) -> Bool {
        let row = slot / columns
        let column = slot % columns
        guard column + span <= columns else { return false }
        for dy in 0..<span {
            for dx in 0..<span where occupied.contains((row + dy) * columns + column + dx) {
                return false
            }
        }
        return true
    }
}
