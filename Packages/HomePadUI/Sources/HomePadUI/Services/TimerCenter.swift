import AudioToolbox
import Foundation
import HomePadUICore
import Observation

/// Plays the alert tone on a loop until stopped. Injected so previews and tests stay silent.
@MainActor
public protocol AlertSounding: AnyObject {
    func startAlert()
    func stopAlert()
}

@MainActor
public final class SystemAlertSound: AlertSounding {
    private var loop: Task<Void, Never>?
    /// The system "alarm" tone.
    private let soundID: SystemSoundID = 1005
    private let maximumRepeats = 24

    public init() {}

    public func startAlert() {
        guard loop == nil else { return }
        let sound = soundID
        let repeats = maximumRepeats
        loop = Task { [weak self] in
            for _ in 0..<repeats {
                AudioServicesPlayAlertSound(sound)
                try? await Task.sleep(for: .seconds(2.5))
                if Task.isCancelled { return }
            }
            self?.loop = nil
        }
    }

    public func stopAlert() {
        loop?.cancel()
        loop = nil
    }
}

@MainActor
public final class SilentAlertSound: AlertSounding {
    public init() {}
    public func startAlert() {}
    public func stopAlert() {}
}

/// Owns the hub's timers: runs the engine against the wall clock, saves it, and raises the alert
/// when a timer finishes.
@MainActor
@Observable
public final class TimerCenter {
    public private(set) var engine: TimerEngine
    /// Timers that finished and have not been dismissed, oldest first.
    public private(set) var ringing: [HubTimer] = []
    public private(set) var lastError: TimerEngineError?
    /// While true a finished timer still shows, and makes no sound. Do Not Disturb sets it.
    public var isSilenced = false {
        didSet {
            if isSilenced {
                sound.stopAlert()
            }
        }
    }

    @ObservationIgnored private let store: any SnapshotStore
    @ObservationIgnored private let sound: any AlertSounding
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        store: any SnapshotStore = InMemorySnapshotStore(),
        sound: any AlertSounding = SilentAlertSound(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.sound = sound
        let saved = (try? store.load()).flatMap { try? TimerCodec.decode($0) } ?? []
        engine = TimerEngine(timers: saved, clock: clock)
        // Timers that ran out while the app was not running show as finished without ringing.
        engine.tick()
        reschedule()
    }

    public var strip: TimerStrip {
        TimerStrip(engine: engine, limit: 3)
    }

    @discardableResult
    public func add(name: String, duration: TimeInterval) -> HubTimer? {
        var created: HubTimer?
        mutate { engine throws(TimerEngineError) in created = try engine.add(name: name, duration: duration) }
        return created
    }

    public func start(_ id: UUID) {
        mutate { engine throws(TimerEngineError) in try engine.start(id) }
    }

    public func pause(_ id: UUID) {
        mutate { engine throws(TimerEngineError) in try engine.pause(id) }
    }

    public func resume(_ id: UUID) {
        mutate { engine throws(TimerEngineError) in try engine.resume(id) }
    }

    public func reset(_ id: UUID) {
        mutate { engine throws(TimerEngineError) in try engine.reset(id) }
        silence(id)
    }

    public func remove(_ id: UUID) {
        mutate { engine throws(TimerEngineError) in try engine.remove(id) }
        silence(id)
    }

    /// Stops the alert for every finished timer and returns them to idle.
    public func dismissRinging() {
        for timer in ringing {
            mutate { engine throws(TimerEngineError) in try engine.reset(timer.id) }
        }
        ringing = []
        sound.stopAlert()
    }

    private func silence(_ id: UUID) {
        ringing.removeAll { $0.id == id }
        if ringing.isEmpty {
            sound.stopAlert()
        }
    }

    private func mutate(_ change: (inout TimerEngine) throws(TimerEngineError) -> Void) {
        do {
            try change(&engine)
            lastError = nil
        } catch {
            lastError = error
        }
        persist()
        reschedule()
    }

    private func persist() {
        guard let data = try? TimerCodec.encode(engine.timers) else { return }
        try? store.save(data)
    }

    /// Polls only while something is running, so an idle hub does no timer work.
    private func reschedule() {
        loop?.cancel()
        loop = nil
        guard engine.nextCompletionDate != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                guard self.advance() else { return }
            }
        }
    }

    /// Returns whether any timer is still running.
    private func advance() -> Bool {
        guard let next = engine.nextCompletionDate else { return false }
        if next <= engine.now {
            let finished = engine.tick()
            if !finished.isEmpty {
                ringing += finished
                persist()
                if !isSilenced {
                    sound.startAlert()
                }
            }
        }
        return engine.nextCompletionDate != nil
    }
}

/// Owns the hub's alarms and rings them while the app is in front.
@MainActor
@Observable
public final class AlarmCenter {
    public private(set) var book: AlarmBook
    public private(set) var ringing: HubAlarm?
    public private(set) var lastError: AlarmError?
    /// While true a due alarm still shows, and makes no sound. Do Not Disturb sets it.
    public var isSilenced = false {
        didSet {
            if isSilenced {
                sound.stopAlert()
            }
        }
    }

    @ObservationIgnored private let store: any SnapshotStore
    @ObservationIgnored private let sound: any AlertSounding
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var lastCheck: Date
    @ObservationIgnored private var snoozed: (alarm: HubAlarm, until: Date)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        store: any SnapshotStore = InMemorySnapshotStore(),
        sound: any AlertSounding = SilentAlertSound(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.sound = sound
        self.clock = clock
        lastCheck = clock()
        book = AlarmBook(alarms: (try? store.load()).flatMap { try? AlarmCodec.decode($0) } ?? [])
    }

    public func nextAlarm(calendar: Calendar = .current) -> (alarm: HubAlarm, date: Date)? {
        AlarmSchedule.nextAlarm(in: book.alarms, after: clock(), calendar: calendar)
    }

    /// Starts watching the clock. Safe to call more than once.
    public func start(calendar: Calendar = .current) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                self.check(calendar: calendar)
            }
        }
    }

    public func add(hour: Int, minute: Int, label: String, repeatDays: Set<Weekday>) {
        mutate { book throws(AlarmError) in try book.add(hour: hour, minute: minute, label: label, repeatDays: repeatDays) }
    }

    public func setEnabled(_ enabled: Bool, id: UUID) {
        mutate { book throws(AlarmError) in try book.setEnabled(enabled, id: id) }
    }

    public func remove(_ id: UUID) {
        mutate { book throws(AlarmError) in try book.remove(id) }
    }

    public func stopRinging() {
        ringing = nil
        sound.stopAlert()
    }

    public func snooze() {
        guard let alarm = ringing else { return }
        snoozed = (alarm, AlarmSchedule.snoozeDate(from: clock()))
        stopRinging()
    }

    private func check(calendar: Calendar) {
        let now = clock()
        defer { lastCheck = now }
        if let pending = snoozed, pending.until <= now {
            snoozed = nil
            ring(pending.alarm)
            return
        }
        guard let due = AlarmSchedule.dueAlarms(in: book.alarms, after: lastCheck, upTo: now, calendar: calendar).first else { return }
        mutate { book throws(AlarmError) in try book.markFired(due.id) }
        ring(due)
    }

    private func ring(_ alarm: HubAlarm) {
        ringing = alarm
        if !isSilenced {
            sound.startAlert()
        }
    }

    private func mutate(_ change: (inout AlarmBook) throws(AlarmError) -> Void) {
        do {
            try change(&book)
            lastError = nil
        } catch {
            lastError = error
        }
        guard let data = try? AlarmCodec.encode(book.alarms) else { return }
        try? store.save(data)
    }
}
