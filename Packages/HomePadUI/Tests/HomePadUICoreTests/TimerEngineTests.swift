import Foundation
import Testing
@testable import HomePadUICore

@Suite struct TimerEngineTests {
    private func makeEngine(limit: Int = TimerEngine.defaultLimit) -> (TimerEngine, TestClock) {
        let clock = TestClock()
        return (TimerEngine(limit: limit, clock: { clock.now }), clock)
    }

    @Test func add_whenStartingImmediately_thenRunsUntilDuration() throws {
        var (engine, clock) = makeEngine()
        let timer = try engine.add(name: "  Pasta ", duration: 600)
        #expect(timer.name == "Pasta")
        #expect(timer.state == .running(endsAt: clock.now.addingTimeInterval(600)))
        #expect(timer.isRunning && timer.isActive && !timer.isFinished)
        #expect(engine.now == clock.now)
        clock.advance(100)
        #expect(engine.remaining(for: timer) == 500)
        #expect(abs(engine.progress(for: timer) - 1.0 / 6.0) < 1e-9)
    }

    @Test func add_whenNotStarting_thenIdleWithFullDuration() throws {
        var (engine, _) = makeEngine()
        let timer = try engine.add(name: "Tea", duration: 180, startImmediately: false)
        #expect(timer.state == .idle)
        #expect(!timer.isActive)
        #expect(engine.remaining(for: timer) == 180)
        #expect(engine.activeTimers.isEmpty)
    }

    @Test func add_whenDurationInvalid_thenThrows() {
        var (engine, _) = makeEngine()
        #expect(throws: TimerEngineError.invalidDuration) { try engine.add(name: "x", duration: 0) }
        #expect(throws: TimerEngineError.invalidDuration) { try engine.add(name: "x", duration: .infinity) }
        #expect(throws: TimerEngineError.invalidDuration) { try engine.add(name: "x", duration: TimerEngine.maximumDuration + 1) }
    }

    @Test func add_whenLimitReached_thenThrows() throws {
        var (engine, _) = makeEngine(limit: 1)
        try engine.add(name: "one", duration: 10)
        #expect(throws: TimerEngineError.limitReached(1)) { try engine.add(name: "two", duration: 10) }
    }

    @Test func tick_whenEndPassed_thenFinishesOnceAndReportsSoonestFirst() throws {
        var (engine, clock) = makeEngine()
        let long = try engine.add(name: "long", duration: 50)
        let short = try engine.add(name: "short", duration: 20)
        try engine.add(name: "later", duration: 500)
        clock.advance(19)
        let early = engine.tick()
        #expect(early.isEmpty)
        clock.advance(40)
        let finished = engine.tick()
        #expect(finished.map(\.id) == [short.id, long.id])
        #expect(finished.allSatisfy { $0.isFinished })
        let again = engine.tick()
        #expect(again.isEmpty)
        #expect(engine.remaining(for: finished[0]) == 0)
        #expect(engine.progress(for: finished[0]) == 1)
    }

    @Test func pauseAndResume_whenRunning_thenKeepsRemainingTime() throws {
        var (engine, clock) = makeEngine()
        let timer = try engine.add(name: "Eggs", duration: 300)
        clock.advance(120)
        try engine.pause(timer.id)
        #expect(engine.timers[0].state == .paused(remaining: 180))
        clock.advance(1000)
        #expect(engine.remaining(for: engine.timers[0]) == 180)
        let whilePaused = engine.tick()
        #expect(whilePaused.isEmpty)
        try engine.resume(timer.id)
        #expect(engine.timers[0].state == .running(endsAt: clock.now.addingTimeInterval(180)))
    }

    @Test func pause_whenAlreadyExpired_thenFinishesInsteadOfPausingAtZero() throws {
        var (engine, clock) = makeEngine()
        let timer = try engine.add(name: "late", duration: 10)
        clock.advance(11)
        try engine.pause(timer.id)
        #expect(engine.timers[0].isFinished)
    }

    @Test func transitions_whenStateDoesNotAllowThem_thenThrow() throws {
        var (engine, _) = makeEngine()
        let running = try engine.add(name: "running", duration: 10)
        let idle = try engine.add(name: "idle", duration: 10, startImmediately: false)
        #expect(throws: TimerEngineError.invalidTransition(running.id)) { try engine.start(running.id) }
        #expect(throws: TimerEngineError.invalidTransition(running.id)) { try engine.resume(running.id) }
        #expect(throws: TimerEngineError.invalidTransition(idle.id)) { try engine.pause(idle.id) }
        try engine.pause(running.id)
        #expect(throws: TimerEngineError.invalidTransition(running.id)) { try engine.start(running.id) }
    }

    @Test func operations_whenTimerUnknown_thenThrow() {
        var (engine, _) = makeEngine()
        let missing = UUID()
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.start(missing) }
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.pause(missing) }
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.resume(missing) }
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.reset(missing) }
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.remove(missing) }
        #expect(throws: TimerEngineError.unknownTimer(missing)) { try engine.rename(missing, to: "x") }
    }

    @Test func startAndReset_whenFinished_thenRestartOrReturnToIdle() throws {
        var (engine, clock) = makeEngine()
        let timer = try engine.add(name: "again", duration: 10)
        clock.advance(10)
        engine.tick()
        try engine.start(timer.id)
        #expect(engine.timers[0].state == .running(endsAt: clock.now.addingTimeInterval(10)))
        try engine.reset(timer.id)
        #expect(engine.timers[0].state == .idle)
        try engine.start(timer.id)
        #expect(engine.timers[0].isRunning)
    }

    @Test func renameAndRemove_whenKnown_thenApply() throws {
        var (engine, _) = makeEngine()
        let timer = try engine.add(name: "a", duration: 10)
        try engine.rename(timer.id, to: " Rice\n")
        #expect(engine.timers[0].name == "Rice")
        try engine.remove(timer.id)
        #expect(engine.timers.isEmpty)
    }

    @Test func activeTimers_whenMixedStates_thenFinishedThenRunningThenPaused() throws {
        var (engine, clock) = makeEngine()
        let pausedLong = try engine.add(name: "pausedLong", duration: 900)
        let runningLong = try engine.add(name: "runningLong", duration: 400)
        let runningShort = try engine.add(name: "runningShort", duration: 100)
        let done = try engine.add(name: "done", duration: 5)
        let pausedShort = try engine.add(name: "pausedShort", duration: 50)
        try engine.add(name: "idle", duration: 30, startImmediately: false)
        try engine.pause(pausedLong.id)
        try engine.pause(pausedShort.id)
        clock.advance(6)
        engine.tick()
        #expect(engine.activeTimers.map(\.id) == [done.id, runningShort.id, runningLong.id, pausedShort.id, pausedLong.id])
        #expect(engine.nextCompletionDate == clock.now.addingTimeInterval(94))
    }

    @Test func activeTimers_whenTied_thenOldestFirst() throws {
        let clock = TestClock()
        var engine = TimerEngine(clock: { clock.now })
        let first = try engine.add(name: "first", duration: 60, startImmediately: false)
        clock.advance(1)
        let second = try engine.add(name: "second", duration: 60, startImmediately: false)
        try engine.start(second.id)
        clock.advance(1)
        try engine.start(first.id)
        try engine.pause(first.id)
        try engine.pause(second.id)
        clock.advance(5)
        try engine.resume(second.id)
        try engine.pause(second.id)
        #expect(engine.remaining(for: engine.timers[0]) == 60)
        #expect(engine.remaining(for: engine.timers[1]) == 59)
        #expect(engine.activeTimers.map(\.id) == [second.id, first.id])
        var tied = TimerEngine(timers: [
            HubTimer(name: "b", duration: 30, state: .paused(remaining: 10), createdAt: clock.now.addingTimeInterval(5)),
            HubTimer(name: "a", duration: 30, state: .paused(remaining: 10), createdAt: clock.now),
        ], clock: { clock.now })
        #expect(tied.activeTimers.map(\.name) == ["a", "b"])
        #expect(tied.nextCompletionDate == nil)
        let none = tied.tick()
        #expect(none.isEmpty)
    }

    @Test func progress_whenDurationIsZero_thenComplete() {
        let engine = TimerEngine()
        #expect(abs(engine.now.timeIntervalSinceNow) < 5)
        #expect(!HubTimer(name: "idle", duration: 5, createdAt: Fixtures.date()).isRunning)
        let timer = HubTimer(name: "zero", duration: 0, createdAt: Fixtures.date())
        #expect(engine.progress(for: timer) == 1)
    }

    @Test func codec_whenRoundTripped_thenTimersSurvive() throws {
        var (engine, clock) = makeEngine()
        try engine.add(name: "run", duration: 90)
        let paused = try engine.add(name: "pause", duration: 60)
        try engine.pause(paused.id)
        try engine.add(name: "idle", duration: 30, startImmediately: false)
        let done = try engine.add(name: "done", duration: 1)
        clock.advance(2)
        engine.tick()
        #expect(engine.timers.first { $0.id == done.id }?.isFinished == true)
        let decoded = try TimerCodec.decode(TimerCodec.encode(engine.timers))
        #expect(decoded == engine.timers)
    }

    @Test func codec_whenVersionUnknownOrCorrupt_thenTypedError() throws {
        let future = Data(#"{"version":99,"payload":[]}"#.utf8)
        #expect(throws: SnapshotCodecError.unsupportedVersion(99)) { try TimerCodec.decode(future) }
        #expect(throws: SnapshotCodecError.corrupt) { try TimerCodec.decode(Data("nope".utf8)) }
        let wrongShape = Data(#"{"version":1,"payload":{"a":1}}"#.utf8)
        #expect(throws: SnapshotCodecError.corrupt) { try TimerCodec.decode(wrongShape) }
    }

    @Test func strip_whenMoreTimersThanFit_thenShowsMostUrgentAndCountsRest() throws {
        var (engine, clock) = makeEngine()
        let pasta = try engine.add(name: "Pasta", duration: 600)
        let sauce = try engine.add(name: "Sauce", duration: 300)
        let bread = try engine.add(name: "Bread", duration: 60)
        try engine.pause(pasta.id)
        clock.advance(61)
        engine.tick()
        let strip = TimerStrip(engine: engine, limit: 2)
        #expect(strip.entries.map(\.id) == [bread.id, sauce.id])
        #expect(strip.entries[0].isFinished && strip.entries[0].countdown == "0:00")
        #expect(strip.entries[1].countdown == "3:59" && !strip.entries[1].isPaused)
        #expect(strip.overflowCount == 1)
        let all = TimerStrip(engine: engine, limit: 5)
        #expect(all.entries.last?.isPaused == true)
        #expect(all.overflowCount == 0)
        #expect(TimerStrip(engine: engine, limit: -1).entries.isEmpty)
    }
}

@Suite struct TimerRingTests {
    @Test func ticks_whenNothingElapsed_thenAllLitAndStartAtTopCenter() {
        let ticks = TimerRing.ticks(count: 60, progress: 0)
        #expect(ticks.count == 60)
        #expect(ticks.allSatisfy { $0.isLit })
        #expect(abs(ticks[0].x - 0.5) < 1e-9 && abs(ticks[0].y - 0.12) < 1e-9 && ticks[0].rotation == 0)
    }

    @Test func ticks_whenQuarterElapsed_thenFirstQuarterGoesDark() {
        let ticks = TimerRing.ticks(count: 60, progress: 0.25)
        #expect(ticks.prefix(15).allSatisfy { !$0.isLit })
        #expect(ticks.dropFirst(15).allSatisfy { $0.isLit })
        #expect(TimerRing.ticks(count: 60, progress: 2).allSatisfy { !$0.isLit })
        #expect(TimerRing.ticks(count: 60, progress: .nan).allSatisfy { $0.isLit })
    }

    @Test func ticks_whenWalkingTheRing_thenStayOnTheRoundedSquare() {
        let ticks = TimerRing.ticks(count: 120, progress: 0, inset: 0.1, cornerRadius: 0.2)
        for tick in ticks {
            #expect(tick.x >= 0.1 - 1e-9 && tick.x <= 0.9 + 1e-9)
            #expect(tick.y >= 0.1 - 1e-9 && tick.y <= 0.9 + 1e-9)
        }
        let right = ticks[30]
        let bottom = ticks[60]
        let left = ticks[90]
        #expect(abs(right.x - 0.9) < 1e-9 && abs(right.y - 0.5) < 1e-9 && right.rotation == 90)
        #expect(abs(bottom.x - 0.5) < 1e-9 && abs(bottom.y - 0.9) < 1e-9 && bottom.rotation == 180)
        #expect(abs(left.x - 0.1) < 1e-9 && abs(left.y - 0.5) < 1e-9 && left.rotation == 270)
        #expect(ticks[15].rotation > 0 && ticks[15].rotation < 90)
        #expect(ticks[45].rotation > 90 && ticks[45].rotation < 180)
        #expect(ticks[75].rotation > 180 && ticks[75].rotation < 270)
        #expect(ticks[105].rotation > 270 && ticks[105].rotation < 360)
        #expect(ticks[119].rotation == 0 && ticks[119].x < 0.5)
    }

    @Test func ticks_whenSquareCornersOrNoTicks_thenStillValid() {
        #expect(TimerRing.ticks(count: 0, progress: 0).isEmpty)
        let square = TimerRing.ticks(count: 8, progress: 0, inset: 0, cornerRadius: 0)
        #expect(abs(square[1].x - 1) < 1e-9 && abs(square[1].y - 0) < 1e-9)
        #expect(abs(square[2].x - 1) < 1e-9 && abs(square[2].y - 0.5) < 1e-9)
        let circle = TimerRing.ticks(count: 4, progress: 0, inset: 0, cornerRadius: 5)
        #expect(abs(circle[1].x - 1) < 1e-9 && abs(circle[1].y - 0.5) < 1e-9)
    }
}
