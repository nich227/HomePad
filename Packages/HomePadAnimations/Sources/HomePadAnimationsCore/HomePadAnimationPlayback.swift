/// What an animation view should be doing, decided from its inputs.
public enum HomePadAnimationPlayback: Equatable, Sendable {
    /// Hold whatever frame is showing.
    case paused
    /// Show the last frame without motion.
    case finalFrame
    /// Play one pass from the first frame.
    case playOnce
    /// Repeat from the first frame.
    case loop

    /// Reduce Motion wins over everything: the view shows the last frame and never moves. A
    /// play-once pass that has finished keeps its last frame, so going offscreen and back does
    /// not replay it. Motion needs both `isPlaying` and `isVisible`.
    public static func resolve(
        loop: Bool,
        isPlaying: Bool,
        isVisible: Bool,
        reduceMotion: Bool,
        hasFinished: Bool
    ) -> HomePadAnimationPlayback {
        if reduceMotion || (hasFinished && !loop) { return .finalFrame }
        guard isPlaying, isVisible else { return .paused }
        return loop ? .loop : .playOnce
    }

    /// Whether a play-once pass still owes its finish callback while Reduce Motion replaces the
    /// motion with the last frame. The view reports it after the pass would have ended, so flows
    /// that wait for the callback keep their pacing.
    public static func owesFinishWithoutMotion(
        loop: Bool,
        isPlaying: Bool,
        isVisible: Bool,
        reduceMotion: Bool,
        hasFinished: Bool
    ) -> Bool {
        reduceMotion && !loop && isPlaying && isVisible && !hasFinished
    }

    /// Whether the end of a pass should reach the caller. An interrupted pass, a loop, and a
    /// second report for the same pass do not.
    public static func shouldReportFinish(loop: Bool, completed: Bool, hasFinished: Bool) -> Bool {
        completed && !loop && !hasFinished
    }
}
