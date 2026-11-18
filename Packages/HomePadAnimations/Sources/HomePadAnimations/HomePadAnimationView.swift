import HomePadAnimationsCore
import Lottie
import SwiftUI

/// Plays one of the bundled Lottie animations, scaled to fit the space it is given.
///
/// The view is decorative and hidden from accessibility. With Reduce Motion on it shows the last
/// frame and never moves. It stops animating while it is offscreen, while the app is in the
/// background, and while `isPlaying` is false.
public struct HomePadAnimationView: View {
    private let animation: HomePadAnimation
    private let loop: Bool
    private let isPlaying: Bool
    private let tint: Color?
    private var finishAction: (@MainActor () -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.self) private var environment
    @State private var isOnScreen = false
    @State private var hasFinished = false

    /// `loop` defaults to true for every animation. Use `init(authored:)` to follow
    /// `HomePadAnimation.loops` instead.
    public init(_ animation: HomePadAnimation, loop: Bool = true, isPlaying: Bool = true) {
        self.init(animation, loop: loop, isPlaying: isPlaying, tint: nil)
    }

    /// `tint` recolors the accent parts of the animation. Nil keeps them white. Animations whose
    /// `supportsTint` is false ignore it.
    public init(_ animation: HomePadAnimation, loop: Bool = true, isPlaying: Bool = true, tint: Color?) {
        self.animation = animation
        self.loop = loop
        self.isPlaying = isPlaying
        self.tint = tint
    }

    /// Plays the animation the way it was authored: looping animations repeat and the others
    /// play once and hold their last frame.
    public init(authored animation: HomePadAnimation, isPlaying: Bool = true, tint: Color? = nil) {
        self.init(animation, loop: animation.loops, isPlaying: isPlaying, tint: tint)
    }

    /// Calls `action` once when a play-once pass reaches its last frame. Looping playback never
    /// calls it. With Reduce Motion on, the call comes after the time the pass would have taken.
    /// Setting `isPlaying` to false and back to true starts a new pass.
    public func onFinished(_ action: @escaping @MainActor () -> Void) -> HomePadAnimationView {
        var copy = self
        copy.finishAction = action
        return copy
    }

    public var body: some View {
        LottieView(animation: AnimationStore.animation(for: animation))
            .resizable()
            .playbackMode(playbackMode)
            .animationDidFinish { completed in
                finish(completed: completed)
            }
            .configure { view in
                applyTint(to: view)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onChange(of: isPlaying) { _, playing in
                if playing { hasFinished = false }
            }
            .onChange(of: animation) {
                hasFinished = false
            }
            .task(id: owesFinishWithoutMotion) {
                guard owesFinishWithoutMotion else { return }
                guard (try? await Task.sleep(for: .seconds(animation.duration))) != nil else { return }
                finish(completed: true)
            }
    }

    private var isVisible: Bool {
        isOnScreen && scenePhase != .background
    }

    private var playbackMode: LottiePlaybackMode {
        let playback = HomePadAnimationPlayback.resolve(
            loop: loop, isPlaying: isPlaying, isVisible: isVisible,
            reduceMotion: reduceMotion, hasFinished: hasFinished
        )
        switch playback {
        case .paused:
            return .paused(at: .currentFrame)
        case .finalFrame:
            return .paused(at: .progress(1))
        case .playOnce:
            return .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
        case .loop:
            return .playing(.fromProgress(0, toProgress: 1, loopMode: .loop))
        }
    }

    private var owesFinishWithoutMotion: Bool {
        HomePadAnimationPlayback.owesFinishWithoutMotion(
            loop: loop, isPlaying: isPlaying, isVisible: isVisible,
            reduceMotion: reduceMotion, hasFinished: hasFinished
        )
    }

    private func finish(completed: Bool) {
        guard
            HomePadAnimationPlayback.shouldReportFinish(loop: loop, completed: completed, hasFinished: hasFinished)
        else { return }
        hasFinished = true
        finishAction?()
    }

    private func applyTint(to view: LottieAnimationView) {
        let keypath = AnimationKeypath(keypath: HomePadAnimationKeypath.tintColor)
        let current = (view.valueProviders[keypath] as? ColorValueProvider)?.color
        guard animation.supportsTint, let tint else {
            if current != nil { view.removeValueProvider(for: keypath) }
            return
        }
        let resolved = tint.resolve(in: environment)
        let color = LottieColor(
            r: Double(min(max(resolved.red, 0), 1)),
            g: Double(min(max(resolved.green, 0), 1)),
            b: Double(min(max(resolved.blue, 0), 1)),
            a: Double(resolved.opacity)
        )
        if current != color {
            view.setValueProvider(ColorValueProvider(color), keypath: keypath)
        }
    }
}

/// Decoded animations, kept so that a view update does not parse JSON again. Lottie reloads its
/// layer tree whenever it is handed a different animation object, so every view showing the same
/// case has to get the same object.
@MainActor
private enum AnimationStore {
    private static var decoded: [HomePadAnimation: LottieAnimation] = [:]

    static func animation(for animation: HomePadAnimation) -> LottieAnimation? {
        if let cached = decoded[animation] { return cached }
        guard let fresh = try? LottieAnimation.from(data: animation.data()) else { return nil }
        decoded[animation] = fresh
        return fresh
    }
}
