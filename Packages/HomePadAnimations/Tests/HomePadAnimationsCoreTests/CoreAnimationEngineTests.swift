import Foundation
import Lottie
import QuartzCore
import Testing
@testable import HomePadAnimationsCore

/// The app plays the files with the Core Animation rendering engine. With the automatic engine
/// option Lottie starts on that engine and switches to the main thread engine when it meets a
/// feature the Core Animation engine cannot draw, so the engine in use after setup tells whether
/// a file is compatible.
@MainActor @Suite struct CoreAnimationEngineTests {
    private final class Log {
        var messages: [String] = []
    }

    private func engineAfterSetup(_ data: Data) throws -> (engine: RenderingEngine?, messages: [String]) {
        let log = Log()
        let logger = LottieLogger(
            assert: { condition, message, _, _ in if !condition() { log.messages.append(message()) } },
            assertionFailure: { message, _, _ in log.messages.append(message()) },
            warn: { message, _, _ in log.messages.append(message()) }
        )
        let layer = LottieAnimationLayer(
            animation: try LottieAnimation.from(data: data),
            configuration: LottieConfiguration(renderingEngine: .automatic),
            logger: logger
        )
        layer.currentProgress = 0.5
        layer.layoutIfNeeded()
        layer.sublayers?.forEach { $0.display() }
        return (layer.currentRenderingEngine, log.messages)
    }

    @Test(arguments: HomePadAnimation.allCases)
    func setup_whenBundledAnimation_thenStaysOnCoreAnimationWithoutIssues(animation: HomePadAnimation) throws {
        let result = try engineAfterSetup(animation.data())
        #expect(result.engine == .coreAnimation)
        #expect(result.messages.isEmpty)
    }

    /// Proves the check above can fail: a trim on a filled shape is outside the engine's subset.
    @Test func setup_whenAnimationTrimsAFill_thenFallsBackToMainThread() throws {
        let text = try #require(String(data: try HomePadAnimation.listening.data(), encoding: .utf8))
        let trim = #"{"ty":"tm","nm":"Trim","s":{"a":0,"k":0},"e":{"a":0,"k":50},"o":{"a":0,"k":0},"m":1},"#
        let broken = text.replacingOccurrences(of: #"{"ty":"fl""#, with: trim + #"{"ty":"fl""#)
        #expect(broken != text)
        let result = try engineAfterSetup(Data(broken.utf8))
        #expect(result.engine == .mainThread)
        #expect(!result.messages.isEmpty)
    }
}
