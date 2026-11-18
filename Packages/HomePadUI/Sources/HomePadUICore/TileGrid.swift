import Foundation
import HomePadCore

/// The grid a face lays its tiles on. It is chosen from the space, never from a device: four by
/// three on a wide screen, three by four on a tall one, three by three on a square, and fewer,
/// larger cells where the space is small.
public struct TileGrid: Equatable, Sendable {
    /// No cell side goes below this, in points, when a coarser grid would avoid it.
    public static let minimumCellSide = 120.0
    public static let countRange = 2...4
    public static let maximumCells = 12

    public let columns: Int
    public let rows: Int

    public var cellCount: Int { columns * rows }

    public init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }

    /// The grid whose cells are closest to square, preferring more cells when two are equally
    /// square, and never one whose cells are too small to press unless nothing larger fits.
    public init(width: Double, height: Double) {
        var best = (columns: 2, rows: 2, score: -Double.infinity)
        for columns in Self.countRange {
            for rows in Self.countRange where columns * rows <= Self.maximumCells {
                let cellWidth = width / Double(columns)
                let cellHeight = height / Double(rows)
                let shorter = min(cellWidth, cellHeight)
                let longer = max(cellWidth, cellHeight)
                guard longer > 0 else { continue }
                var score = shorter / longer * (1 + 0.05 * Double(columns * rows))
                if shorter < Self.minimumCellSide {
                    // Too small to press: only chosen when every grid is, and then the one
                    // with the largest cells.
                    score = shorter / Self.minimumCellSide - 10
                }
                if score > best.score {
                    best = (columns, rows, score)
                }
            }
        }
        self.init(columns: best.columns, rows: best.rows)
    }
}

/// A tile's place on the grid, in cells.
public struct TilePlacement: Equatable, Sendable {
    public let column: Int
    public let row: Int
    public let columnSpan: Int
    public let rowSpan: Int

    public init(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }

    /// The frame for a grid drawn in `width` by `height` with `gap` between cells.
    public func frame(in grid: TileGrid, width: Double, height: Double, gap: Double) -> CanvasFrame {
        let cellWidth = (width - gap * Double(grid.columns - 1)) / Double(grid.columns)
        let cellHeight = (height - gap * Double(grid.rows - 1)) / Double(grid.rows)
        return CanvasFrame(
            x: Double(column) * (cellWidth + gap),
            y: Double(row) * (cellHeight + gap),
            width: cellWidth * Double(columnSpan) + gap * Double(columnSpan - 1),
            height: cellHeight * Double(rowSpan) + gap * Double(rowSpan - 1)
        )
    }
}

public enum TileGridPacker {
    public struct Span: Equatable, Sendable {
        public let columns: Int
        public let rows: Int

        public init(columns: Int = 1, rows: Int = 1) {
            self.columns = columns
            self.rows = rows
        }

        public static let single = Span()
        /// The large tile, as the thermostat is on Home Modular.
        public static let large = Span(columns: 2, rows: 2)
    }

    /// Places tiles in order, each in the first free spot reading across then down. A tile too
    /// large for the grid shrinks to one cell. A tile with no room left gets nil, so the caller
    /// leaves it out instead of scrolling.
    public static func pack(_ spans: [Span], in grid: TileGrid) -> [TilePlacement?] {
        var taken = Array(repeating: Array(repeating: false, count: grid.columns), count: grid.rows)
        return spans.map { requested in
            let fits = requested.columns <= grid.columns && requested.rows <= grid.rows
            let span = fits ? requested : .single
            for row in 0...(grid.rows - span.rows) {
                for column in 0...(grid.columns - span.columns) where isFree(taken, column: column, row: row, span: span) {
                    for takenRow in row..<(row + span.rows) {
                        for takenColumn in column..<(column + span.columns) {
                            taken[takenRow][takenColumn] = true
                        }
                    }
                    return TilePlacement(column: column, row: row, columnSpan: span.columns, rowSpan: span.rows)
                }
            }
            return nil
        }
    }

    private static func isFree(_ taken: [[Bool]], column: Int, row: Int, span: Span) -> Bool {
        for takenRow in row..<(row + span.rows) {
            for takenColumn in column..<(column + span.columns) where taken[takenRow][takenColumn] {
                return false
            }
        }
        return true
    }
}

/// Sizes of the Home Screen: a row of widgets, then a grid of app icons that scrolls up and
/// down. Widths are in points and `unit` is a hundredth of the shorter side of the canvas, the
/// measure everything on the hub is drawn in.
public enum HomeScreenGrid {
    public static let minimumColumns = 4
    public static let maximumColumns = 8
    public static let widgetRange = 2...6
    /// The width one icon column wants, in units: the icon and the space beside it.
    public static let columnPitch = 22.3
    /// The side a widget wants in the widget row, in units.
    public static let widgetSide = 27.0
    public static let margin = 8.5
    public static let gap = 4.2

    /// Four columns, and more when the width allows.
    public static func columns(width: Double, unit: Double) -> Int {
        guard unit > 0 else { return minimumColumns }
        let usable = width - 2 * margin * unit + gap * unit
        let fitting = Int((usable / (columnPitch * unit)).rounded(.down))
        return min(maximumColumns, max(minimumColumns, fitting))
    }

    /// How many widgets the row holds. It never scrolls sideways, so the rest are left out.
    public static func widgetCount(width: Double, unit: Double) -> Int {
        guard unit > 0 else { return widgetRange.lowerBound }
        let usable = width - 2 * margin * unit + gap * unit
        let fitting = Int((usable / ((widgetSide + gap) * unit)).rounded())
        return min(widgetRange.upperBound, max(widgetRange.lowerBound, fitting))
    }
}

/// One live thing in the pill at the top of a face.
public struct LivePillItem: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case timer, nowPlaying, note, page
        /// A member was just recognized. Shown for a moment, then gone.
        case recognized
    }

    public let id: String
    public let kind: Kind
    public let symbolName: String
    public let title: String
    public let detail: String
    /// Belongs to one person or to the household's private exchanges. Guests never see it.
    public let isPersonal: Bool

    public init(id: String, kind: Kind, symbolName: String, title: String, detail: String = "", isPersonal: Bool = false) {
        self.id = id
        self.kind = kind
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.isPersonal = isPersonal
    }

    /// The app the item belongs to, if any. A household note belongs to Intercom.
    public var app: HubApp? {
        switch kind {
        case .timer: .timers
        case .nowPlaying: .music
        case .note: .intercom
        case .page: .beam
        case .recognized: nil
        }
    }

    /// The app a tap on the item opens: its own, when that app has an icon right now. A note
    /// opens nothing while no package is supplying Intercom.
    public func destination(available: Set<HubApp>) -> HubApp? {
        app.flatMap { VisibilityPolicy.isListed($0, available: available) ? $0 : nil }
    }
}

public enum LivePill {
    public static let limit = 4
    /// How long the confirmation of a recognized member stays in the pill.
    public static let recognitionSeconds: TimeInterval = 4

    /// The confirmation first, then timers, then what is playing, then whatever the other
    /// packages report. A guest, and a member whose personal content is still locked, get only
    /// the shared items.
    public static func items(
        recognizedName: String? = nil,
        timers: TimerStrip,
        nowPlaying: NowPlaying?,
        extras: [LivePillItem],
        context: AudienceContext
    ) -> [LivePillItem] {
        var items: [LivePillItem] = []
        if let recognizedName, !context.isGuest {
            items.append(LivePillItem(id: "recognized", kind: .recognized, symbolName: "person.crop.circle.badge.checkmark", title: recognizedName))
        }
        items += timers.entries.map { entry in
            LivePillItem(
                id: "timer.\(entry.id.uuidString)",
                kind: .timer,
                symbolName: "timer",
                title: entry.countdown,
                detail: entry.name
            )
        }
        if let nowPlaying, nowPlaying.isPlaying {
            items.append(LivePillItem(id: "nowPlaying", kind: .nowPlaying, symbolName: "music.note", title: nowPlaying.title, detail: nowPlaying.artist))
        }
        items += extras.filter { !$0.isPersonal || context.isPersonalContentUnlocked }
        return Array(items.prefix(limit))
    }
}

/// The thermostat dial: a three-quarter circle from the lowest to the highest target.
public enum ThermostatDial {
    /// Degrees clockwise from straight up. The gap is at the bottom.
    public static let startAngle = -135.0
    public static let endAngle = 135.0

    /// Where the knob sits for a target, clamped to the range a thermostat accepts.
    public static func angle(forCelsius celsius: Double) -> Double {
        let range = ThermostatMath.celsiusRange
        let clamped = min(max(celsius, range.lowerBound), range.upperBound)
        let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return startAngle + fraction * (endAngle - startAngle)
    }

    /// The target for a touch at a point relative to the dial's center, x to the right and y
    /// down. A touch in the gap at the bottom goes to the nearer end. The result is a whole
    /// degree in the unit shown.
    public static func celsius(forOffsetX x: Double, y: Double, unit: TemperatureUnit) -> Double {
        var angle = atan2(x, -y) * 180 / .pi
        angle = min(max(angle, startAngle), endAngle)
        let range = ThermostatMath.celsiusRange
        let celsius = range.lowerBound + (angle - startAngle) / (endAngle - startAngle) * (range.upperBound - range.lowerBound)
        switch unit {
        case .celsius:
            return celsius.rounded()
        case .fahrenheit:
            let fahrenheit = (celsius * 9 / 5 + 32).rounded()
            return min(max((fahrenheit - 32) * 5 / 9, range.lowerBound), range.upperBound)
        }
    }
}

/// The Home Modular face: one large tile, a clock, a camera when there is one, and a dock of
/// quick toggles, packed onto whatever grid the space gives.
public enum HomeModularLayout {
    public enum Slot: Hashable, Sendable {
        case hero
        case clock
        case tile(Int)
    }

    public struct Placed: Equatable, Sendable {
        public let slot: Slot
        public let placement: TilePlacement
    }

    /// The hero takes two columns and two rows, the clock sits beside it, and the small tiles
    /// fill what is left in reading order. `tileCount` is how many small tiles there are to show.
    public static func placements(in grid: TileGrid, tileCount: Int) -> [Placed] {
        let room = max(0, grid.cellCount - 5)
        let shown = min(max(0, tileCount), room)
        let slots: [Slot] = [.hero, .clock] + (0..<shown).map(Slot.tile)
        let spans: [TileGridPacker.Span] = [.large, .single] + Array(repeating: .single, count: shown)
        let packed = TileGridPacker.pack(spans, in: grid)
        return zip(slots, packed).compactMap { slot, placement in
            placement.map { Placed(slot: slot, placement: $0) }
        }
    }
}

/// The Modular face: a few large widgets with no backgrounds, on black. Two by two on a square,
/// and a third column or row where the screen is wider or taller.
public enum ModularLayout {
    public enum Widget: String, CaseIterable, Sendable {
        case date, clock, weather, nowPlaying, home, timers
    }

    public static func grid(width: Double, height: Double) -> TileGrid {
        guard width > 0, height > 0 else { return TileGrid(columns: 2, rows: 2) }
        let aspect = width / height
        if aspect >= 1.2 { return TileGrid(columns: 3, rows: 2) }
        if aspect <= 1 / 1.2 { return TileGrid(columns: 2, rows: 3) }
        return TileGrid(columns: 2, rows: 2)
    }

    /// The widgets in reading order, as many as the grid holds.
    public static func widgets(for grid: TileGrid) -> [Widget] {
        Array(Widget.allCases.prefix(grid.cellCount))
    }
}

/// The dimmer: a tall pill that fills from the bottom.
public enum DimmerMath {
    /// The brightness for a touch `y` points down from the top of a track `height` points tall.
    public static func brightness(forY y: Double, height: Double) -> Int {
        guard height > 0 else { return 0 }
        return Int((min(max(1 - y / height, 0), 1) * 100).rounded())
    }

    /// Color temperatures offered under the slider, in mireds, warm to cool.
    public static let temperatureSwatches = [454, 370, 286, 222, 154]
}
