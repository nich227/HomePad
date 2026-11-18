import Testing
@testable import HomePadAnimationsCore

@Suite struct HomePadAnimationPlaybackTests {
    private func resolve(
        loop: Bool = true,
        isPlaying: Bool = true,
        isVisible: Bool = true,
        reduceMotion: Bool = false,
        hasFinished: Bool = false
    ) -> HomePadAnimationPlayback {
        .resolve(
            loop: loop, isPlaying: isPlaying, isVisible: isVisible,
            reduceMotion: reduceMotion, hasFinished: hasFinished
        )
    }

    @Test func resolve_whenLoopPlayingAndVisible_thenLoops() {
        #expect(resolve() == .loop)
    }

    @Test func resolve_whenPlayOncePlayingAndVisible_thenPlaysOnce() {
        #expect(resolve(loop: false) == .playOnce)
    }

    @Test(arguments: [true, false])
    func resolve_whenNotPlaying_thenPauses(loop: Bool) {
        #expect(resolve(loop: loop, isPlaying: false) == .paused)
    }

    @Test(arguments: [true, false])
    func resolve_whenOffscreen_thenPauses(loop: Bool) {
        #expect(resolve(loop: loop, isVisible: false) == .paused)
    }

    @Test(arguments: [true, false], [true, false])
    func resolve_whenReduceMotion_thenShowsFinalFrameWhateverElse(loop: Bool, active: Bool) {
        #expect(resolve(loop: loop, isPlaying: active, isVisible: active, reduceMotion: true) == .finalFrame)
    }

    @Test(arguments: [true, false], [true, false])
    func resolve_whenPlayOnceFinished_thenHoldsFinalFrame(isPlaying: Bool, isVisible: Bool) {
        let mode = resolve(loop: false, isPlaying: isPlaying, isVisible: isVisible, hasFinished: true)
        #expect(mode == .finalFrame)
    }

    @Test func resolve_whenLoopMarkedFinished_thenKeepsLooping() {
        #expect(resolve(hasFinished: true) == .loop)
    }

    @Test func owesFinishWithoutMotion_whenPlayOnceUnderReduceMotion_thenIsTrue() {
        #expect(HomePadAnimationPlayback.owesFinishWithoutMotion(
            loop: false, isPlaying: true, isVisible: true, reduceMotion: true, hasFinished: false
        ))
    }

    @Test(arguments: [
        [true, true, true, true, false],
        [false, false, true, true, false],
        [false, true, false, true, false],
        [false, true, true, false, false],
        [false, true, true, true, true],
    ])
    func owesFinishWithoutMotion_whenAnyConditionFails_thenIsFalse(flags: [Bool]) {
        #expect(!HomePadAnimationPlayback.owesFinishWithoutMotion(
            loop: flags[0], isPlaying: flags[1], isVisible: flags[2], reduceMotion: flags[3], hasFinished: flags[4]
        ))
    }

    @Test func shouldReportFinish_whenPlayOnceCompletes_thenIsTrue() {
        #expect(HomePadAnimationPlayback.shouldReportFinish(loop: false, completed: true, hasFinished: false))
    }

    @Test func shouldReportFinish_whenInterrupted_thenIsFalse() {
        #expect(!HomePadAnimationPlayback.shouldReportFinish(loop: false, completed: false, hasFinished: false))
    }

    @Test func shouldReportFinish_whenLoop_thenIsFalse() {
        #expect(!HomePadAnimationPlayback.shouldReportFinish(loop: true, completed: true, hasFinished: false))
    }

    @Test func shouldReportFinish_whenAlreadyReported_thenIsFalse() {
        #expect(!HomePadAnimationPlayback.shouldReportFinish(loop: false, completed: true, hasFinished: true))
    }
}
