import Foundation
import HomePadCore

// Layout decisions for displays that change size and fold. They take sizes and size classes, never
// a device name, so the same rules serve an iPhone, a folding iPhone, and an iPad.

/// A part of the companion. In a narrow space each is a tab.
public enum CompanionSection: String, CaseIterable, Identifiable, Sendable {
    case hub, beam, apps, people

    public var id: String { rawValue }
}

public enum CompanionArrangement: Equatable, Sendable {
    /// One section at a time, chosen from a tab bar.
    case tabs
    /// What the hub shows and the list of sections on the leading side, one section beside it.
    case twoColumn
}

public enum CompanionLayoutPolicy {
    /// Below this width two columns would each be narrower than a small phone, whatever the
    /// size class says.
    public static let minimumTwoColumnWidth = 560.0

    /// Sections listed in the leading column. The hub's status is always visible there, so it is
    /// not a section to choose.
    public static let sidebarSections: [CompanionSection] = [.beam, .apps, .people]

    public static func arrangement(isRegularWidth: Bool, width: Double) -> CompanionArrangement {
        isRegularWidth && width >= minimumTwoColumnWidth ? .twoColumn : .tabs
    }

    /// The leading column's share of the width, and the range it stays within.
    public static let sidebarFraction = 0.38
    public static let sidebarWidthRange = 220.0...320.0
    /// The least width the trailing column needs to be useful beside the leading one.
    public static let minimumDetailWidth = 280.0

    /// The width the leading column asks for. It is a preference, not a fixed size: the split
    /// view may give it less or more, and adjusts it around a fold.
    public static func sidebarWidth(forWidth width: Double) -> Double {
        min(max(width * sidebarFraction, sidebarWidthRange.lowerBound), sidebarWidthRange.upperBound)
    }

    /// What the trailing column shows for a selection. The selection itself is kept, so going
    /// back to tabs returns to the tab the person left.
    public static func detail(for selection: CompanionSection) -> CompanionSection {
        selection == .hub ? .beam : selection
    }
}

/// How the hub's two panes, the canvas and everything around it, share the display.
public enum HubPanePlacement: Equatable, Sendable {
    /// One on top of the other across the whole display: the canvas, with the status and the
    /// second column in the space around it.
    case together
    /// Each on its own side of a fold.
    case apart
}

public enum HubPanePolicy {
    /// A pane with less than this share of the container's area has been given one side of a
    /// fold. Safe areas alone never take this much.
    public static let apartAreaFraction = 0.75

    public static func placement(containerWidth: Double, containerHeight: Double, paneWidth: Double, paneHeight: Double) -> HubPanePlacement {
        let container = containerWidth * containerHeight
        guard container > 0 else { return .together }
        return paneWidth * paneHeight < container * apartAreaFraction ? .apart : .together
    }
}

public struct CanvasInsets: Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public static let zero = CanvasInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

extension CanvasFrame {
    /// How far to move in from each edge of this frame so nothing drawn inside it sits under an
    /// obstacle, such as a camera or the edge of the safe area. Each obstacle is cleared from
    /// the edge it is closest to, which moves content the least.
    public func insets(clearing obstacles: [CanvasFrame]) -> CanvasInsets {
        var insets = CanvasInsets.zero
        for obstacle in obstacles {
            let fromTop = obstacle.y + obstacle.height - y
            let fromBottom = y + height - obstacle.y
            let fromLeading = obstacle.x + obstacle.width - x
            let fromTrailing = x + width - obstacle.x
            guard obstacle.width > 0, obstacle.height > 0, fromTop > 0, fromBottom > 0, fromLeading > 0, fromTrailing > 0 else { continue }
            let least = min(fromTop, fromBottom, fromLeading, fromTrailing)
            if least == fromTop {
                insets.top = max(insets.top, fromTop)
            } else if least == fromBottom {
                insets.bottom = max(insets.bottom, fromBottom)
            } else if least == fromLeading {
                insets.leading = max(insets.leading, fromLeading)
            } else {
                insets.trailing = max(insets.trailing, fromTrailing)
            }
        }
        return insets
    }

    /// The safe area of a container as four obstacles along its edges.
    public static func edges(of safeArea: CanvasInsets, width: Double, height: Double) -> [CanvasFrame] {
        [
            CanvasFrame(x: 0, y: 0, width: width, height: safeArea.top),
            CanvasFrame(x: 0, y: height - safeArea.bottom, width: width, height: safeArea.bottom),
            CanvasFrame(x: 0, y: 0, width: safeArea.leading, height: height),
            CanvasFrame(x: width - safeArea.trailing, y: 0, width: safeArea.trailing, height: height),
        ]
    }
}

/// The pane beside the canvas when a fold gives it a side of its own: the status in a strip
/// across the top and the widgets below.
public struct ChromePanelLayout: Equatable, Sendable {
    /// Share of the pane's shorter side given to the status strip.
    public static let statusFraction = 0.16

    public let status: CanvasFrame
    public let side: CanvasFrame
    /// The side of the canvas this pane is drawn to match: the largest square that fits it.
    public let unitSide: Double

    public init(width: Double, height: Double) {
        let availableWidth = max(0, width)
        let availableHeight = max(0, height)
        unitSide = min(availableWidth, availableHeight)
        let strip = min(availableHeight, unitSide * Self.statusFraction)
        status = CanvasFrame(x: 0, y: 0, width: availableWidth, height: strip)
        side = CanvasFrame(x: 0, y: strip, width: availableWidth, height: availableHeight - strip)
    }
}

/// How many widgets the space beside the canvas holds, and in what grid. It picks the grid that
/// shows the most widget area without drawing a widget much larger than on the Home Screen.
public struct SidePanelGrid: Equatable, Sendable {
    public static let maximumCount = 4
    /// A widget may grow this much past its Home Screen size before more widgets are better.
    public static let growthLimit = 1.25

    public let columns: Int
    public let rows: Int
    public let tileWidth: Double
    public let tileHeight: Double

    public var count: Int { columns * rows }

    public init(width: Double, height: Double, gap: Double, preferredSide: Double) {
        var best = (columns: 1, rows: 1, score: -1.0)
        for columns in 1...Self.maximumCount {
            for rows in 1...(Self.maximumCount / columns) {
                let tile = Self.tile(width: width, height: height, gap: gap, columns: columns, rows: rows)
                let side = min(tile.width, tile.height, preferredSide * Self.growthLimit)
                let score = side > 0 ? Double(columns * rows) * side * side : 0
                if score > best.score {
                    best = (columns, rows, score)
                }
            }
        }
        columns = best.columns
        rows = best.rows
        let tile = Self.tile(width: width, height: height, gap: gap, columns: columns, rows: rows)
        tileWidth = max(0, tile.width)
        tileHeight = max(0, tile.height)
    }

    private static func tile(width: Double, height: Double, gap: Double, columns: Int, rows: Int) -> (width: Double, height: Double) {
        (
            (width - gap * Double(columns - 1)) / Double(columns),
            (height - gap * Double(rows - 1)) / Double(rows)
        )
    }
}

/// A size in points that a UI test frames the whole app to, so a display this machine cannot
/// simulate can still be captured. The size classes are what a display of that size reports.
public struct TestViewport: Equatable, Sendable {
    /// A display whose shorter side is at least this long is regular width in both
    /// orientations. A folding iPhone's inner display is; its outer display is compact.
    public static let regularShorterSide = 600.0
    /// From this height up a display is regular height. A phone on its side is compact.
    public static let regularHeight = 480.0

    public let width: Double
    public let height: Double

    public var isRegularWidth: Bool { min(width, height) >= Self.regularShorterSide }
    public var isRegularHeight: Bool { height >= Self.regularHeight }

    /// Reads "626x890". Nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }
}
