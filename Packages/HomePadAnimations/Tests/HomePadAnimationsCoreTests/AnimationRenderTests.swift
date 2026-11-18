import Foundation
import Lottie
import Testing
@testable import HomePadAnimationsCore

/// Draws frames into a bitmap and checks the pixels.
@MainActor @Suite struct AnimationRenderTests {
    private static let red = LottieColor(r: 1, g: 0, b: 0, a: 1)

    private func isPureRed(_ pixel: Bitmap.Pixel) -> Bool {
        pixel.alpha > 0 && pixel.red == pixel.alpha && pixel.green == 0 && pixel.blue == 0
    }

    private func sampleFrames(_ animation: HomePadAnimation) -> [Double] {
        (0...8).map { Double(animation.frameCount) * Double($0) / 8 }
    }

    @Test(arguments: HomePadAnimation.allCases)
    func lastFrame_whenRendered_thenDrawsSomething(animation: HomePadAnimation) throws {
        let bitmap = try AnimationRenderer(animation).frame(Double(animation.frameCount))
        #expect(bitmap.inkedCount > 1500)
    }

    @Test(arguments: HomePadAnimation.allCases)
    func everyFrame_whenRendered_thenLeavesTheCanvasCornersTransparent(animation: HomePadAnimation) throws {
        let renderer = try AnimationRenderer(animation)
        for frame in sampleFrames(animation) {
            let bitmap = try renderer.frame(frame)
            for (x, y) in [(0, 0), (399, 0), (0, 399), (399, 399)] {
                #expect(bitmap.pixel(x: x, y: y).alpha == 0, "frame \(frame) at \(x),\(y)")
            }
        }
    }

    @Test(arguments: HomePadAnimation.allCases.filter(\.loops))
    func loop_whenRendered_thenLastFrameMatchesFirstFrame(animation: HomePadAnimation) throws {
        let renderer = try AnimationRenderer(animation)
        let first = try renderer.frame(0)
        let middle = try renderer.frame(Double(animation.frameCount) / 2)
        let last = try renderer.frame(Double(animation.frameCount))
        #expect(first == last)
        #expect(first != middle)
    }

    @Test(arguments: HomePadAnimation.allCases.filter { !$0.loops })
    func playOnce_whenRendered_thenStartsEmptyAndEndsDrawn(animation: HomePadAnimation) throws {
        let renderer = try AnimationRenderer(animation)
        let first = try renderer.frame(0)
        let last = try renderer.frame(Double(animation.frameCount))
        #expect(last.inkedCount > first.inkedCount)
        #expect(first != last)
    }

    /// The ring sits around a live camera preview, so nothing may be drawn inside it.
    @Test func faceScan_whenRendered_thenCenterStaysTransparent() throws {
        let renderer = try AnimationRenderer(.faceScan)
        for frame in sampleFrames(.faceScan) {
            let bitmap = try renderer.frame(frame)
            var covered = 0
            for y in 0..<400 {
                for x in 0..<400 where (x - 200) * (x - 200) + (y - 200) * (y - 200) < 160 * 160 {
                    if bitmap.pixel(x: x, y: y).alpha > 0 { covered += 1 }
                }
            }
            #expect(covered == 0, "frame \(frame)")
        }
    }

    @Test(arguments: HomePadAnimation.allCases.filter(\.supportsTint))
    func tint_whenAnimationSupportsIt_thenRecolorsOnlyTheTintParts(animation: HomePadAnimation) throws {
        let plain = try AnimationRenderer(animation)
        let tinted = try AnimationRenderer(animation, tint: Self.red)
        var recoloredFrames = 0
        for frame in sampleFrames(animation) {
            let before = try plain.frame(frame)
            let after = try tinted.frame(frame)
            #expect(before.count(where: isPureRed) == 0, "frame \(frame)")
            #expect(after.inkedCount == before.inkedCount, "frame \(frame)")
            if after.count(where: isPureRed) > 0 { recoloredFrames += 1 }
        }
        #expect(recoloredFrames >= 4)
        let lastFrame = try tinted.frame(Double(animation.frameCount))
        #expect(lastFrame.count(where: isPureRed) > 100)
    }

    @Test func tint_whenHello_thenChangesNothing() throws {
        let frame = Double(HomePadAnimation.hello.frameCount)
        let before = try AnimationRenderer(.hello).frame(frame)
        let after = try AnimationRenderer(.hello, tint: Self.red).frame(frame)
        #expect(before == after)
    }

    @Test(arguments: [HomePadAnimation.beamIncoming, .beamSending, .pairing, .guest])
    func tint_whenAnimationHasNeutralOutline_thenOutlineStaysWhite(animation: HomePadAnimation) throws {
        let bitmap = try AnimationRenderer(animation, tint: Self.red).frame(Double(animation.frameCount))
        let white = bitmap.count { $0.alpha == 255 && $0.red == 255 && $0.green == 255 && $0.blue == 255 }
        #expect(white > 500)
    }

    @Test func hello_whenFinished_thenShowsStripesInsideAWhiteOutline() throws {
        let bitmap = try AnimationRenderer(.hello).frame(Double(HomePadAnimation.hello.frameCount))
        let green = bitmap.pixel(x: 200, y: 90)
        #expect(green == Bitmap.Pixel(red: 0x61, green: 0xBB, blue: 0x46, alpha: 255))
        let blue = bitmap.pixel(x: 200, y: 252)
        #expect(blue == Bitmap.Pixel(red: 0x00, green: 0x9D, blue: 0xDC, alpha: 255))
        let outline = bitmap.pixel(x: 200, y: 56)
        #expect(outline == Bitmap.Pixel(red: 255, green: 255, blue: 255, alpha: 255))
    }

    @Test func success_whenFinished_thenShowsRingAndCheck() throws {
        let renderer = try AnimationRenderer(.success)
        let last = try renderer.frame(90)
        #expect(last.pixel(x: 200, y: 76).alpha == 255)
        #expect(last.pixel(x: 184, y: 242).alpha == 255)
        let ringOnly = try renderer.frame(30)
        #expect(ringOnly.pixel(x: 184, y: 242).alpha == 0)
    }
}
