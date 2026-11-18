import Foundation
import Testing
@testable import HomePadFaceCore

@Suite struct SceneBrightnessTests {
    @Test func sceneExposureValue_whenExposureGiven_thenFollowsTheExposureEquation() throws {
        let base = CameraExposure(iso: 100, exposureDuration: 1.0 / 30, aperture: 2, targetOffset: 0)
        #expect(abs(try #require(base.sceneExposureValue) - log2(120)) < 1e-9)
        let moreSensitive = CameraExposure(iso: 200, exposureDuration: 1.0 / 30, aperture: 2, targetOffset: 0)
        #expect(abs(try #require(moreSensitive.sceneExposureValue) - (log2(120) - 1)) < 1e-9)
        let longer = CameraExposure(iso: 100, exposureDuration: 1.0 / 15, aperture: 2, targetOffset: 0)
        #expect(abs(try #require(longer.sceneExposureValue) - (log2(120) - 1)) < 1e-9)
    }

    @Test func sceneExposureValue_whenCameraCannotLiftTheScene_thenTargetOffsetLowersIt() throws {
        let maxedOut = CameraExposure(iso: 100, exposureDuration: 1.0 / 30, aperture: 2, targetOffset: -3)
        #expect(abs(try #require(maxedOut.sceneExposureValue) - (log2(120) - 3)) < 1e-9)
    }

    @Test func sceneExposureValue_whenDeviceReportedNothingUsable_thenNil() {
        #expect(CameraExposure(iso: 0, exposureDuration: 0.03, aperture: 2, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: .nan, exposureDuration: 0.03, aperture: 2, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: 100, exposureDuration: 0, aperture: 2, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: 100, exposureDuration: .nan, aperture: 2, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: 100, exposureDuration: 0.03, aperture: 0, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: 100, exposureDuration: 0.03, aperture: .infinity, targetOffset: 0).sceneExposureValue == nil)
        #expect(CameraExposure(iso: 100, exposureDuration: 0.03, aperture: 2, targetOffset: .nan).sceneExposureValue == nil)
    }

    @Test func level_whenExposureValueGiven_thenMapsTheRangeOntoZeroToOne() {
        #expect(SceneBrightness.level(exposureValue: -2) == 0)
        #expect(SceneBrightness.level(exposureValue: 10) == 1)
        #expect(SceneBrightness.level(exposureValue: 4) == 0.5)
        #expect(SceneBrightness.level(exposureValue: -9) == 0)
        #expect(SceneBrightness.level(exposureValue: 15) == 1)
    }

    @Test func approximateLux_whenExposureValueGiven_thenDoublesPerStop() {
        #expect(SceneBrightness.approximateLux(exposureValue: 0) == 2.5)
        #expect(SceneBrightness.approximateLux(exposureValue: 2) == 10)
    }

    @Test func level_whenExposureIsKnown_thenItWinsOverPixelBrightness() throws {
        // A dark room that auto exposure has lifted to mid gray: long exposure, high ISO.
        let lifted = CameraExposure(iso: 2000, exposureDuration: 0.2, aperture: 2.2, targetOffset: -1)
        let level = try #require(SceneBrightness.level(for: SceneLightSample(exposure: lifted, meanLuma: 0.5)))
        #expect(level < 0.15)
    }

    @Test func level_whenExposureIsUnknown_thenPixelBrightnessIsTheFallback() {
        let unusable = CameraExposure(iso: 0, exposureDuration: 0, aperture: 0, targetOffset: 0)
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: nil, meanLuma: 0.4)) == 0.4)
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: unusable, meanLuma: 0.4)) == 0.4)
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: nil, meanLuma: 1.7)) == 1)
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: nil, meanLuma: -0.2)) == 0)
    }

    @Test func level_whenNothingIsKnown_thenNil() {
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: nil, meanLuma: nil)) == nil)
        #expect(SceneBrightness.level(for: SceneLightSample(exposure: nil, meanLuma: .nan)) == nil)
    }

    @Test func meanLuma_whenFullRange_thenDividesBy255() {
        #expect(SceneBrightness.meanLuma(sum: 255 * 4, count: 4, isVideoRange: false) == 1)
        #expect(SceneBrightness.meanLuma(sum: 0, count: 4, isVideoRange: false) == 0)
        #expect(abs((SceneBrightness.meanLuma(sum: 510, count: 4, isVideoRange: false) ?? 0) - 0.5) < 1e-9)
    }

    @Test func meanLuma_whenVideoRange_thenSixteenIsBlackAnd235IsWhite() {
        #expect(SceneBrightness.meanLuma(sum: 16 * 10, count: 10, isVideoRange: true) == 0)
        #expect(SceneBrightness.meanLuma(sum: 235 * 10, count: 10, isVideoRange: true) == 1)
        #expect(SceneBrightness.meanLuma(sum: 0, count: 10, isVideoRange: true) == 0)
        #expect(SceneBrightness.meanLuma(sum: 255 * 10, count: 10, isVideoRange: true) == 1)
        #expect(abs((SceneBrightness.meanLuma(sum: 1255, count: 10, isVideoRange: true) ?? 0) - 0.5) < 1e-9)
    }

    @Test func meanLuma_whenNoSamples_thenNil() {
        #expect(SceneBrightness.meanLuma(sum: 0, count: 0, isVideoRange: false) == nil)
        #expect(SceneBrightness.meanLuma(sum: -5, count: 3, isVideoRange: false) == nil)
    }
}

@Suite struct AmbientLightEstimatorTests {
    /// No smoothing and no settling time, so each sample is the brightness the decision is made
    /// on. Dark at or below 0.22, lit at or above 0.3, 8 s dwell.
    private let direct = AmbientLightPolicy(smoothingTime: 0, settlingTime: 0)

    private func sample(_ level: Double) -> SceneLightSample {
        SceneLightSample(exposure: nil, meanLuma: level)
    }

    @Test func update_whenCameraJustStarted_thenUnknownUntilExposureHasSettled() {
        var estimator = AmbientLightEstimator()
        #expect(estimator.update(with: sample(0.05), at: 10) == false)
        #expect(estimator.update(with: sample(0.6), at: 11) == false)
        #expect(estimator.level == nil)
        #expect(estimator.isRoomDark == nil)
        #expect(estimator.update(with: sample(0.6), at: 11.5) == true)
        #expect(estimator.level == 0.6)
        #expect(estimator.isRoomDark == false)
    }

    @Test func update_whenFirstUsableSampleIsDark_thenDarkAtOnce() {
        var estimator = AmbientLightEstimator(policy: direct)
        #expect(estimator.update(with: sample(0.1), at: 0) == true)
        #expect(estimator.isRoomDark == true)
        var atTheBound = AmbientLightEstimator(policy: direct)
        atTheBound.update(with: sample(0.22), at: 0)
        #expect(atTheBound.isRoomDark == true)
        var between = AmbientLightEstimator(policy: direct)
        between.update(with: sample(0.26), at: 0)
        #expect(between.isRoomDark == false)
    }

    @Test func update_whenRoomGoesDarkAndStaysDark_thenDarkOnlyAfterTheDwell() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.6), at: 0)
        #expect(estimator.update(with: sample(0.1), at: 1) == true)
        #expect(estimator.isRoomDark == false)
        #expect(estimator.level == 0.1)
        #expect(estimator.update(with: sample(0.1), at: 8.9) == false)
        #expect(estimator.isRoomDark == false)
        #expect(estimator.update(with: sample(0.1), at: 9) == true)
        #expect(estimator.isRoomDark == true)
    }

    @Test func update_whenAShadowPasses_thenDecisionDoesNotFlip() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.6), at: 0)
        for second in 1...6 {
            estimator.update(with: sample(0.1), at: Double(second))
        }
        estimator.update(with: sample(0.6), at: 7)
        for second in 8...15 {
            estimator.update(with: sample(0.1), at: Double(second))
            #expect(estimator.isRoomDark == false)
        }
        estimator.update(with: sample(0.1), at: 16)
        #expect(estimator.isRoomDark == true)
    }

    @Test func update_whenALightFlashesInADarkRoom_thenRoomStaysDark() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.1), at: 0)
        for second in 1...5 {
            estimator.update(with: sample(0.8), at: Double(second))
        }
        estimator.update(with: sample(0.1), at: 6)
        #expect(estimator.isRoomDark == true)
        for second in 7...14 {
            estimator.update(with: sample(0.8), at: Double(second))
            #expect(estimator.isRoomDark == true)
        }
        estimator.update(with: sample(0.8), at: 15)
        #expect(estimator.isRoomDark == false)
    }

    @Test func update_whenBrightnessSitsBetweenTheTwoBounds_thenDecisionHoldsEitherWay() {
        var dark = AmbientLightEstimator(policy: direct)
        dark.update(with: sample(0.1), at: 0)
        var lit = AmbientLightEstimator(policy: direct)
        lit.update(with: sample(0.6), at: 0)
        for second in 1...60 {
            dark.update(with: sample(0.26), at: Double(second))
            lit.update(with: sample(0.26), at: Double(second))
        }
        #expect(dark.isRoomDark == true)
        #expect(lit.isRoomDark == false)
    }

    @Test func update_whenBrightnessReachesABoundExactly_thenThatCountsAsPastIt() {
        var lit = AmbientLightEstimator(policy: direct)
        lit.update(with: sample(0.6), at: 0)
        lit.update(with: sample(0.22), at: 1)
        lit.update(with: sample(0.22), at: 9)
        #expect(lit.isRoomDark == true)
        lit.update(with: sample(0.3), at: 10)
        lit.update(with: sample(0.3), at: 18)
        #expect(lit.isRoomDark == false)
    }

    @Test func update_whenSmoothing_thenLevelFollowsOverTheSmoothingTime() throws {
        var estimator = AmbientLightEstimator(policy: AmbientLightPolicy(smoothingTime: 2, settlingTime: 0))
        estimator.update(with: sample(0.6), at: 0)
        estimator.update(with: sample(0), at: 2)
        #expect(abs(try #require(estimator.level) - 0.6 * exp(-1)) < 1e-9)
    }

    @Test func update_whenBrightnessMovesLessThanTheReportingStep_thenLevelIsNotReportedAgain() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.6), at: 0)
        #expect(estimator.update(with: sample(0.61), at: 1) == false)
        #expect(estimator.update(with: sample(0.6), at: 2) == false)
        #expect(estimator.level == 0.6)
        #expect(estimator.update(with: sample(0.63), at: 3) == true)
        #expect(estimator.level == 0.63)
    }

    @Test func update_whenReportingStepIsZero_thenUnchangedBrightnessIsNotReported() {
        var estimator = AmbientLightEstimator(policy: AmbientLightPolicy(smoothingTime: 0, settlingTime: 0, reportingStep: 0))
        estimator.update(with: sample(0.6), at: 0)
        #expect(estimator.update(with: sample(0.6), at: 1) == false)
        #expect(estimator.update(with: sample(0.601), at: 2) == true)
    }

    @Test func update_whenFrameHasNoLightReading_thenNothingChanges() {
        var estimator = AmbientLightEstimator(policy: direct)
        #expect(estimator.update(with: nil, at: 0) == false)
        #expect(estimator.update(with: SceneLightSample(exposure: nil, meanLuma: nil), at: 1) == false)
        #expect(estimator.level == nil)
        estimator.update(with: sample(0.6), at: 2)
        #expect(estimator.update(with: nil, at: 3) == false)
        #expect(estimator.level == 0.6)
        #expect(estimator.isRoomDark == false)
    }

    @Test func update_whenClockGoesBackward_thenTheWaitStartsOver() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.6), at: 100)
        estimator.update(with: sample(0.1), at: 101)
        estimator.update(with: sample(0.1), at: 5)
        estimator.update(with: sample(0.1), at: 12)
        #expect(estimator.isRoomDark == false)
        estimator.update(with: sample(0.1), at: 13)
        #expect(estimator.isRoomDark == true)
    }

    @Test func update_whenClockGoesBackwardWhileSettling_thenSettlingStartsOver() {
        var estimator = AmbientLightEstimator(policy: AmbientLightPolicy(smoothingTime: 0, settlingTime: 2))
        estimator.update(with: sample(0.6), at: 50)
        #expect(estimator.update(with: sample(0.6), at: 3) == false)
        #expect(estimator.update(with: sample(0.6), at: 4.9) == false)
        #expect(estimator.update(with: sample(0.6), at: 5) == true)
    }

    @Test func update_whenExposureSaysDarkWhilePixelsLookBright_thenDark() {
        var estimator = AmbientLightEstimator(policy: direct)
        let lifted = CameraExposure(iso: 2000, exposureDuration: 0.2, aperture: 2.2, targetOffset: -1)
        estimator.update(with: SceneLightSample(exposure: lifted, meanLuma: 0.5), at: 0)
        #expect(estimator.isRoomDark == true)
        var daylight = AmbientLightEstimator(policy: direct)
        let short = CameraExposure(iso: 50, exposureDuration: 1.0 / 120, aperture: 2.2, targetOffset: 0)
        daylight.update(with: SceneLightSample(exposure: short, meanLuma: 0.5), at: 0)
        #expect(daylight.isRoomDark == false)
        #expect((daylight.level ?? 0) > 0.8)
    }

    @Test func reset_whenRoomIsKnown_thenUnknownAgain() {
        var estimator = AmbientLightEstimator(policy: direct)
        estimator.update(with: sample(0.1), at: 0)
        estimator.reset()
        #expect(estimator.level == nil)
        #expect(estimator.isRoomDark == nil)
    }

    @Test func policy_whenValuesOutOfRange_thenClamped() {
        let policy = AmbientLightPolicy(smoothingTime: -1, settlingTime: -1, darkEnter: 0.4, darkExit: 0.2, minimumDwell: -1, reportingStep: -1)
        #expect(policy.smoothingTime == 0)
        #expect(policy.settlingTime == 0)
        #expect(policy.darkExit == 0.4)
        #expect(policy.minimumDwell == 0)
        #expect(policy.reportingStep == 0)
        #expect(AmbientLightEstimator().policy == AmbientLightPolicy())
    }
}
