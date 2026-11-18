import Foundation

public struct HubTimer: Identifiable, Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished(at: Date)
    }

    public let id: UUID
    public var name: String
    public let duration: TimeInterval
    public fileprivate(set) var state: State
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, duration: TimeInterval, state: State = .idle, createdAt: Date) {
        self.id = id
        self.name = name
        self.duration = duration
        self.state = state
        self.createdAt = createdAt
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    /// Running, paused, or finished and waiting to be dismissed.
    public var isActive: Bool {
        state != .idle
    }
}

public enum TimerEngineError: Error, Equatable, Sendable {
    case unknownTimer(UUID)
    case invalidDuration
    case invalidTransition(UUID)
    case limitReached(Int)
}

/// Any number of named countdowns. A pure state machine: time only moves when the injected clock
/// says so, and a running timer becomes finished only when `tick` is called.
public struct TimerEngine: Sendable {
    public static let maximumDuration: TimeInterval = 24 * 60 * 60
    public static let defaultLimit = 12

    public private(set) var timers: [HubTimer]
    public let limit: Int
    private let clock: @Sendable () -> Date

    public init(timers: [HubTimer] = [], limit: Int = TimerEngine.defaultLimit, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.timers = timers
        self.limit = limit
        self.clock = clock
    }

    public var now: Date { clock() }

    @discardableResult
    public mutating func add(name: String, duration: TimeInterval, startImmediately: Bool = true, id: UUID = UUID()) throws(TimerEngineError) -> HubTimer {
        guard duration.isFinite, duration >= 1, duration <= Self.maximumDuration else { throw .invalidDuration }
        guard timers.count < limit else { throw .limitReached(limit) }
        let now = clock()
        let timer = HubTimer(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            state: startImmediately ? .running(endsAt: now.addingTimeInterval(duration)) : .idle,
            createdAt: now
        )
        timers.append(timer)
        return timer
    }

    /// Starts an idle timer, or restarts a finished one from its full duration.
    public mutating func start(_ id: UUID) throws(TimerEngineError) {
        let index = try index(of: id)
        switch timers[index].state {
        case .idle, .finished:
            timers[index].state = .running(endsAt: clock().addingTimeInterval(timers[index].duration))
        case .running, .paused:
            throw .invalidTransition(id)
        }
    }

    public mutating func pause(_ id: UUID) throws(TimerEngineError) {
        let index = try index(of: id)
        guard case .running(let endsAt) = timers[index].state else { throw .invalidTransition(id) }
        let remaining = endsAt.timeIntervalSince(clock())
        // A timer that ran out between ticks finishes instead of pausing at zero.
        timers[index].state = remaining > 0 ? .paused(remaining: remaining) : .finished(at: endsAt)
    }

    public mutating func resume(_ id: UUID) throws(TimerEngineError) {
        let index = try index(of: id)
        guard case .paused(let remaining) = timers[index].state else { throw .invalidTransition(id) }
        timers[index].state = .running(endsAt: clock().addingTimeInterval(remaining))
    }

    /// Back to idle with the full duration. Also dismisses a finished timer's alert.
    public mutating func reset(_ id: UUID) throws(TimerEngineError) {
        let index = try index(of: id)
        timers[index].state = .idle
    }

    public mutating func remove(_ id: UUID) throws(TimerEngineError) {
        let index = try index(of: id)
        timers.remove(at: index)
    }

    public mutating func rename(_ id: UUID, to name: String) throws(TimerEngineError) {
        let index = try index(of: id)
        timers[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Moves every running timer whose end has passed to finished. Returns the ones that just
    /// finished, soonest first, so the caller can alert once per timer.
    @discardableResult
    public mutating func tick() -> [HubTimer] {
        let now = clock()
        var finished: [(timer: HubTimer, endedAt: Date)] = []
        for index in timers.indices {
            guard case .running(let endsAt) = timers[index].state, endsAt <= now else { continue }
            timers[index].state = .finished(at: endsAt)
            finished.append((timers[index], endsAt))
        }
        return finished.sorted { $0.endedAt < $1.endedAt }.map(\.timer)
    }

    public func remaining(for timer: HubTimer) -> TimeInterval {
        switch timer.state {
        case .idle: timer.duration
        case .running(let endsAt): max(0, endsAt.timeIntervalSince(clock()))
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    /// 0 when nothing has elapsed, 1 when done.
    public func progress(for timer: HubTimer) -> Double {
        guard timer.duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(for: timer) / timer.duration))
    }

    /// What a face surfaces: finished timers first, then running by soonest end, then paused by
    /// least time left. Idle timers stay in the Timers app only.
    public var activeTimers: [HubTimer] {
        timers.filter(\.isActive).sorted { first, second in
            let firstRank = Self.rank(first)
            let secondRank = Self.rank(second)
            if firstRank != secondRank { return firstRank < secondRank }
            let firstRemaining = remaining(for: first)
            let secondRemaining = remaining(for: second)
            if firstRemaining != secondRemaining { return firstRemaining < secondRemaining }
            return first.createdAt < second.createdAt
        }
    }

    /// When the next running timer ends, so the owner can schedule one wake-up instead of polling.
    public var nextCompletionDate: Date? {
        timers.compactMap { timer -> Date? in
            guard case .running(let endsAt) = timer.state else { return nil }
            return endsAt
        }.min()
    }

    private func index(of id: UUID) throws(TimerEngineError) -> Int {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { throw .unknownTimer(id) }
        return index
    }

    private static func rank(_ timer: HubTimer) -> Int {
        switch timer.state {
        case .finished: 0
        case .running: 1
        case .paused, .idle: 2
        }
    }
}

public enum TimerCodec {
    public static let version = 1
    private static let codec = VersionedCodec<[HubTimer]>(version: version)

    public static func encode(_ timers: [HubTimer]) throws -> Data {
        try codec.encode(timers)
    }

    public static func decode(_ data: Data) throws(SnapshotCodecError) -> [HubTimer] {
        try codec.decode(data)
    }
}

/// One row of the compact strip that faces show while timers run.
public struct TimerStripEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let countdown: String
    public let progress: Double
    public let isFinished: Bool
    public let isPaused: Bool
}

public struct TimerStrip: Equatable, Sendable {
    public let entries: [TimerStripEntry]
    /// Active timers that did not fit.
    public let overflowCount: Int

    public init(engine: TimerEngine, limit: Int) {
        let active = engine.activeTimers
        let shown = active.prefix(max(0, limit))
        entries = shown.map { timer in
            var paused = false
            if case .paused = timer.state { paused = true }
            return TimerStripEntry(
                id: timer.id,
                name: timer.name,
                countdown: DurationText.countdown(engine.remaining(for: timer)),
                progress: engine.progress(for: timer),
                isFinished: timer.isFinished,
                isPaused: paused
            )
        }
        overflowCount = active.count - shown.count
    }
}

/// Geometry of the countdown ring: tick marks spaced evenly around a rounded square.
public enum TimerRing {
    public struct Tick: Equatable, Sendable {
        /// Position in the unit square, origin top leading.
        public let x: Double
        public let y: Double
        /// Direction the tick points, in degrees clockwise from up.
        public let rotation: Double
        public let isLit: Bool
    }

    /// Ticks start at top center and run clockwise. As time elapses the ring empties clockwise
    /// from the top, so the lit ticks are the last ones.
    public static func ticks(count: Int, progress: Double, inset: Double = 0.12, cornerRadius: Double = 0.22) -> [Tick] {
        guard count > 0 else { return [] }
        let clamped = min(1, max(0, progress.isFinite ? progress : 0))
        let unlit = Int((clamped * Double(count)).rounded(.down))
        let side = 1 - 2 * inset
        let radius = min(max(cornerRadius, 0), side / 2)
        let straight = side - 2 * radius
        let arc = Double.pi / 2 * radius
        let perimeter = 4 * straight + 4 * arc
        return (0..<count).map { index in
            let distance = perimeter * Double(index) / Double(count)
            let point = position(distance: distance, inset: inset, straight: straight, radius: radius, arc: arc)
            return Tick(x: point.x, y: point.y, rotation: point.rotation, isLit: index >= unlit)
        }
    }

    private static func position(distance: Double, inset: Double, straight: Double, radius: Double, arc: Double) -> (x: Double, y: Double, rotation: Double) {
        let low = inset
        let high = 1 - inset
        let corners: [(centerX: Double, centerY: Double, start: Double)] = [
            (high - radius, low + radius, 0),
            (high - radius, high - radius, 90),
            (low + radius, high - radius, 180),
            (low + radius, low + radius, 270),
        ]
        let edges: [(x: Double, y: Double, dx: Double, dy: Double, rotation: Double)] = [
            (high, low + radius, 0, 1, 90),
            (high - radius, high, -1, 0, 180),
            (low, high - radius, 0, -1, 270),
            (low + radius, low, 1, 0, 0),
        ]
        func corner(_ quarter: Int, _ travel: Double) -> (x: Double, y: Double, rotation: Double) {
            let angle = corners[quarter].start + travel / max(arc, .leastNonzeroMagnitude) * 90
            let radians = angle * .pi / 180
            return (corners[quarter].centerX + sin(radians) * radius, corners[quarter].centerY - cos(radians) * radius, angle)
        }
        func edge(_ quarter: Int, _ travel: Double) -> (x: Double, y: Double, rotation: Double) {
            let edge = edges[quarter]
            return (edge.x + edge.dx * travel, edge.y + edge.dy * travel, edge.rotation)
        }
        // Clockwise from top center: half the top edge, then corner and edge three times, then the
        // last corner and the other half of the top edge.
        var remaining = distance
        let halfTop = straight / 2
        if remaining <= halfTop { return (0.5 + remaining, low, 0) }
        remaining -= halfTop
        for quarter in 0..<3 {
            if remaining <= arc { return corner(quarter, remaining) }
            remaining -= arc
            if remaining <= straight { return edge(quarter, remaining) }
            remaining -= straight
        }
        if remaining <= arc { return corner(3, remaining) }
        return edge(3, min(remaining - arc, halfTop))
    }
}
