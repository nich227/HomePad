import Foundation
import HomePadCore
import Testing
@testable import HomePadFaceCore

private func close(_ first: CGPoint, _ second: CGPoint, tolerance: Double = 1e-6) -> Bool {
    abs(first.x - second.x) <= tolerance && abs(first.y - second.y) <= tolerance
}

@Suite struct ProximityEstimatorTests {
    /// Standard zones (near under 1 m, far over 2.5 m, 10% hysteresis) without smoothing, so each
    /// sample is the distance the zone is judged on.
    private let unsmoothed = ProximityPolicy(responsiveness: 1)

    private func zone(after distances: [Double], policy: ProximityPolicy? = nil) -> Proximity {
        var estimator = ProximityEstimator(policy: policy ?? unsmoothed)
        for distance in distances {
            estimator.update(distance: distance)
        }
        return estimator.proximity
    }

    @Test func update_whenFirstEstimateArrives_thenZoneFollowsThePlainBoundaries() {
        #expect(zone(after: [0.5]) == .near)
        #expect(zone(after: [0.95]) == .near)
        #expect(zone(after: [1.0]) == .mid)
        #expect(zone(after: [1.8]) == .mid)
        #expect(zone(after: [2.5]) == .mid)
        #expect(zone(after: [2.6]) == .far)
        #expect(zone(after: [4]) == .far)
    }

    @Test func update_whenPersonWalksIn_thenEachZoneStartsABitInsideItsBoundary() {
        #expect(zone(after: [3.0, 2.4]) == .far)
        #expect(zone(after: [3.0, 2.2]) == .mid)
        #expect(zone(after: [3.0, 2.2, 0.95]) == .mid)
        #expect(zone(after: [3.0, 2.2, 0.85]) == .near)
    }

    @Test func update_whenPersonWalksAway_thenEachZoneEndsABitPastItsBoundary() {
        #expect(zone(after: [0.5, 1.05]) == .near)
        #expect(zone(after: [0.5, 1.2]) == .mid)
        #expect(zone(after: [0.5, 1.2, 2.6]) == .mid)
        #expect(zone(after: [0.5, 1.2, 2.8]) == .far)
    }

    @Test func update_whenPersonStandsAtTheNearBoundary_thenZoneDoesNotFlicker() {
        let swaying = (0..<20).map { $0.isMultiple(of: 2) ? 0.95 : 1.05 }
        var fromMid = ProximityEstimator(policy: unsmoothed)
        fromMid.update(distance: 1.3)
        var fromNear = ProximityEstimator(policy: unsmoothed)
        fromNear.update(distance: 0.7)
        for distance in swaying {
            #expect(fromMid.update(distance: distance) == .mid)
            #expect(fromNear.update(distance: distance) == .near)
        }
    }

    @Test func update_whenPersonStandsAtTheFarBoundary_thenZoneDoesNotFlicker() {
        let swaying = (0..<20).map { $0.isMultiple(of: 2) ? 2.35 : 2.65 }
        var fromMid = ProximityEstimator(policy: unsmoothed)
        fromMid.update(distance: 2.0)
        var fromFar = ProximityEstimator(policy: unsmoothed)
        fromFar.update(distance: 3.5)
        for distance in swaying {
            #expect(fromMid.update(distance: distance) == .mid)
            #expect(fromFar.update(distance: distance) == .far)
        }
    }

    @Test func update_whenDistanceJumpsAcrossTheMidZone_thenZoneFollowsInOneStep() {
        #expect(zone(after: [0.5, 3.0]) == .far)
        #expect(zone(after: [3.0, 0.5]) == .near)
    }

    @Test func update_whenDistanceIsMissingOrNotUsable_thenZoneAndDistanceHold() {
        var estimator = ProximityEstimator(policy: unsmoothed)
        #expect(estimator.update(distance: nil) == .far)
        #expect(estimator.distance == nil)
        estimator.update(distance: 0.5)
        for unusable in [nil, Double.nan, .infinity, 0, -1] {
            #expect(estimator.update(distance: unusable) == .near)
        }
        #expect(estimator.distance == 0.5)
    }

    @Test func update_whenSamplesJitter_thenDistanceIsSmoothed() throws {
        var estimator = ProximityEstimator()
        estimator.update(distance: 1.2)
        estimator.update(distance: 2.0)
        #expect(abs(try #require(estimator.distance) - 1.6) < 1e-9)
        #expect(estimator.proximity == .mid)
    }

    @Test func reset_whenNear_thenFarAndDistanceUnknown() {
        var estimator = ProximityEstimator()
        estimator.update(distance: 0.5)
        #expect(estimator.proximity == .near)
        estimator.reset()
        #expect(estimator.proximity == .far)
        #expect(estimator.distance == nil)
    }

    @Test func policy_whenStandard_thenZonesMatchTheSpecification() {
        #expect(ProximityPolicy.standard.nearBoundary == 1)
        #expect(ProximityPolicy.standard.farBoundary == 2.5)
        #expect(ProximityPolicy.standard.hysteresis == 0.1)
    }

    @Test func policy_whenScaled_thenBothBoundariesMove() {
        #expect(abs(ProximityPolicy.closer.nearBoundary - 0.75) < 1e-9)
        #expect(abs(ProximityPolicy.closer.farBoundary - 1.875) < 1e-9)
        #expect(abs(ProximityPolicy.farther.nearBoundary - 1.3) < 1e-9)
        #expect(abs(ProximityPolicy.farther.farBoundary - 3.25) < 1e-9)
        #expect(ProximityPolicy.farther.hysteresis == ProximityPolicy.standard.hysteresis)
        #expect(zone(after: [0.9], policy: .closer) == .mid)
        #expect(zone(after: [1.2], policy: .farther) == .near)
    }

    @Test func policy_whenValuesOutOfRange_thenClamped() {
        let inverted = ProximityPolicy(nearBoundary: 2, farBoundary: 1, hysteresis: 0.2, responsiveness: 7)
        #expect(inverted.nearBoundary == 2)
        #expect(inverted.farBoundary == 2)
        #expect(inverted.hysteresis == 0)
        #expect(inverted.responsiveness == 1)
        let tight = ProximityPolicy(nearBoundary: -1, farBoundary: 0.15, hysteresis: 0.9, responsiveness: 0)
        #expect(tight.nearBoundary == 0.05)
        #expect(abs(tight.hysteresis - 0.5) < 1e-9)
        #expect(tight.responsiveness == 0.05)
        #expect(ProximityPolicy(hysteresis: -1).hysteresis == 0)
    }

    @Test func sizeFraction_whenFrameIsLandscapeOrPortrait_thenRelativeToShorterSide() {
        #expect(ProximityEstimator.sizeFraction(normalizedHeight: 0.5, frameWidth: 1280, frameHeight: 720) == 0.5)
        #expect(ProximityEstimator.sizeFraction(normalizedHeight: 0.25, frameWidth: 720, frameHeight: 1280) == 0.25 * 1280 / 720)
    }

    @Test func sizeFraction_whenInputUnusable_thenZero() {
        #expect(ProximityEstimator.sizeFraction(normalizedHeight: 0.5, frameWidth: 0, frameHeight: 720) == 0)
        #expect(ProximityEstimator.sizeFraction(normalizedHeight: .nan, frameWidth: 10, frameHeight: 10) == 0)
        #expect(ProximityEstimator.sizeFraction(normalizedHeight: -1, frameWidth: 10, frameHeight: 10) == 0)
    }
}

@Suite struct FaceDistanceModelTests {
    private let model = FaceDistanceModel()
    /// Focal length in pixels of a 1280 pixel wide frame with a 60 degree field of view.
    private let focalLength = 640 / tan(Double.pi / 6)

    private func depth(median: Float, valid: Int = 100, of total: Int = 100) -> FaceDepthStatistics {
        FaceDepthStatistics(sampleCount: total, validCount: valid, medianDepth: median, planeResidual: 0.01, centerRelief: 0.02)
    }

    @Test func metersFromFaceSize_whenLandscapeFrame_thenPinholeDistance() throws {
        let meters = try #require(model.metersFromFaceSize(
            normalizedFaceHeight: 0.25, frameWidth: 1280, frameHeight: 720, fieldOfViewDegrees: 60
        ))
        #expect(abs(meters - focalLength * 0.17 / 180) < 1e-9)
        #expect(abs(meters - 1.047) < 0.001)
    }

    @Test func metersFromFaceSize_whenPortraitFrame_thenFieldOfViewSpansTheLongerSide() throws {
        let meters = try #require(model.metersFromFaceSize(
            normalizedFaceHeight: 0.1, frameWidth: 720, frameHeight: 1280, fieldOfViewDegrees: 60
        ))
        #expect(abs(meters - focalLength * 0.17 / 128) < 1e-9)
    }

    @Test func metersFromFaceSize_whenFaceIsHalfAsTall_thenTwiceAsFar() throws {
        let near = try #require(model.metersFromFaceSize(normalizedFaceHeight: 0.3, frameWidth: 1280, frameHeight: 720, fieldOfViewDegrees: 60))
        let far = try #require(model.metersFromFaceSize(normalizedFaceHeight: 0.15, frameWidth: 1280, frameHeight: 720, fieldOfViewDegrees: 60))
        #expect(abs(far - 2 * near) < 1e-9)
    }

    @Test func metersFromFaceSize_whenLensIsWider_thenSameFaceSizeMeansCloser() throws {
        let narrow = try #require(model.metersFromFaceSize(normalizedFaceHeight: 0.2, frameWidth: 1280, frameHeight: 720, fieldOfViewDegrees: 60))
        let wide = try #require(model.metersFromFaceSize(normalizedFaceHeight: 0.2, frameWidth: 1280, frameHeight: 720, fieldOfViewDegrees: 120))
        #expect(wide < narrow)
        #expect(abs(wide / narrow - tan(Double.pi / 6) / tan(Double.pi / 3)) < 1e-9)
    }

    @Test func metersFromFaceSize_whenInputMissingOrNotUsable_thenNil() {
        func meters(height: Double = 0.2, width: Double = 1280, frameHeight: Double = 720, fieldOfView: Double = 60) -> Double? {
            model.metersFromFaceSize(normalizedFaceHeight: height, frameWidth: width, frameHeight: frameHeight, fieldOfViewDegrees: fieldOfView)
        }
        #expect(meters() != nil)
        #expect(meters(height: 0) == nil)
        #expect(meters(height: -0.2) == nil)
        #expect(meters(height: .nan) == nil)
        #expect(meters(width: 0) == nil)
        #expect(meters(frameHeight: 0) == nil)
        #expect(meters(width: .infinity) == nil)
        #expect(meters(fieldOfView: 0) == nil)
        #expect(meters(fieldOfView: 180) == nil)
        #expect(meters(fieldOfView: .nan) == nil)
    }

    @Test func estimate_whenDepthIsPlausible_thenDepthWins() {
        #expect(model.estimate(depth: depth(median: 0.5), faceSizeMeters: 0.62) == FaceDistanceEstimate(meters: 0.5, source: .depth))
        #expect(model.estimate(depth: depth(median: 0.5), faceSizeMeters: nil) == FaceDistanceEstimate(meters: 0.5, source: .depth))
        #expect(model.estimate(depth: faceLikeDepth(), faceSizeMeters: 0.5)?.source == .depth)
    }

    @Test func estimate_whenDepthIsMissing_thenFaceSizeIsUsed() {
        #expect(model.estimate(depth: nil, faceSizeMeters: 1.8) == FaceDistanceEstimate(meters: 1.8, source: .faceSize))
    }

    @Test func estimate_whenDepthIsSparseOrOutOfRange_thenFaceSizeIsUsed() {
        let fallback = FaceDistanceEstimate(meters: 1.8, source: .faceSize)
        #expect(model.estimate(depth: depth(median: 1.7, valid: 10, of: 10), faceSizeMeters: 1.8) == fallback)
        #expect(model.estimate(depth: depth(median: 1.7, valid: 25, of: 100), faceSizeMeters: 1.8) == fallback)
        #expect(model.estimate(depth: depth(median: 0.05), faceSizeMeters: 1.8) == fallback)
        #expect(model.estimate(depth: depth(median: 3.5), faceSizeMeters: 1.8) == fallback)
        #expect(model.estimate(depth: depth(median: 0), faceSizeMeters: 1.8) == fallback)
    }

    @Test func estimate_whenDepthDisagreesWithFaceSizeByFar_thenFaceSizeIsUsed() {
        #expect(model.estimate(depth: depth(median: 0.4), faceSizeMeters: 2.0)?.source == .faceSize)
        #expect(model.estimate(depth: depth(median: 2.9), faceSizeMeters: 0.5)?.source == .faceSize)
        #expect(model.estimate(depth: depth(median: 1.0), faceSizeMeters: 2.0)?.source == .depth)
    }

    @Test func estimate_whenNothingIsUsable_thenNil() {
        #expect(model.estimate(depth: nil, faceSizeMeters: nil) == nil)
        #expect(model.estimate(depth: nil, faceSizeMeters: .nan) == nil)
        #expect(model.estimate(depth: nil, faceSizeMeters: -1) == nil)
        #expect(model.estimate(depth: depth(median: 9), faceSizeMeters: nil) == nil)
    }
}

@Suite struct PrimaryFaceSelectorTests {
    private let selector = PrimaryFaceSelector()

    @Test func select_whenSeveralFaces_thenPicksLargestCenteredOne() {
        let boxes = [
            CGRect(x: 0.1, y: 0.4, width: 0.1, height: 0.1),
            CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3),
            CGRect(x: 0.6, y: 0.4, width: 0.05, height: 0.05),
        ]
        #expect(selector.select(from: boxes) == PrimaryFaceSelection(index: 1, prominentFaceCount: 1))
    }

    @Test func select_whenLargestFaceIsAtTheEdge_thenPicksCenteredOne() {
        let boxes = [
            CGRect(x: 0.0, y: 0.3, width: 0.15, height: 0.4),
            CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            CGRect(x: 0.4, y: 0.85, width: 0.3, height: 0.15),
        ]
        #expect(selector.select(from: boxes)?.index == 1)
    }

    @Test func select_whenTwoFacesOfSimilarSize_thenBothAreProminent() {
        let boxes = [
            CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.2),
            CGRect(x: 0.6, y: 0.4, width: 0.18, height: 0.18),
        ]
        #expect(selector.select(from: boxes) == PrimaryFaceSelection(index: 0, prominentFaceCount: 2))
    }

    @Test func select_whenNoUsableFace_thenNil() {
        #expect(selector.select(from: []) == nil)
        #expect(selector.select(from: [CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2)]) == nil)
        #expect(selector.select(from: [CGRect(x: 0.5, y: 0.5, width: Double.nan, height: 0.2)]) == nil)
        #expect(selector.select(from: [CGRect(x: 0.95, y: 0.5, width: 0.04, height: 0.04)]) == nil)
    }
}

@Suite struct FaceAlignmentTests {
    private let reference = FaceAlignment.referencePoints(outputSize: 112)

    /// The reference layout scaled by 4, rotated by 10 degrees, and moved.
    private func place(_ point: CGPoint) -> CGPoint {
        let angle = radians(10)
        return CGPoint(
            x: 4 * (point.x * cos(angle) - point.y * sin(angle)) + 300,
            y: 4 * (point.x * sin(angle) + point.y * cos(angle)) + 50
        )
    }

    private func placed(_ points: FacePoints) -> FacePoints {
        FacePoints(
            leftEye: place(points.leftEye),
            rightEye: place(points.rightEye),
            nose: points.nose.map(place),
            leftMouth: points.leftMouth.map(place),
            rightMouth: points.rightMouth.map(place)
        )
    }

    @Test func referencePoints_whenOutputIs112_thenStandardFivePointTemplate() {
        #expect(reference.leftEye == CGPoint(x: 38.2946, y: 51.6963))
        #expect(reference.rightEye == CGPoint(x: 73.5318, y: 51.5014))
        #expect(reference.nose == CGPoint(x: 56.0252, y: 71.7366))
        #expect(reference.leftMouth == CGPoint(x: 41.5493, y: 92.3655))
        #expect(reference.rightMouth == CGPoint(x: 70.7299, y: 92.2041))
    }

    @Test func referencePoints_whenOutputSizeChanges_thenPointsScale() throws {
        let larger = FaceAlignment.referencePoints(outputSize: 160)
        #expect(abs(larger.leftEye.x - 38.2946 * 160 / 112) < 1e-9)
        #expect(abs(try #require(larger.rightMouth).y - 92.2041 * 160 / 112) < 1e-9)
    }

    @Test func transform_whenOnlyEyesKnown_thenMapsThemOntoReferenceEyes() throws {
        let left = CGPoint(x: 400, y: 300), right = CGPoint(x: 520, y: 330)
        let transform = try #require(FaceAlignment.transform(from: FacePoints(leftEye: left, rightEye: right), outputSize: 112))
        #expect(close(transform.apply(left), reference.leftEye))
        #expect(close(transform.apply(right), reference.rightEye))
    }

    @Test func transform_whenOnePointOfFiveIsMissing_thenFallsBackToEyesOnly() throws {
        var detected = FacePoints(leftEye: CGPoint(x: 400, y: 300), rightEye: CGPoint(x: 520, y: 330))
        let eyesOnly = FaceAlignment.transform(from: detected, outputSize: 112)
        detected.nose = CGPoint(x: 0, y: 0)
        detected.leftMouth = CGPoint(x: 900, y: 900)
        #expect(FaceAlignment.transform(from: detected, outputSize: 112) == eyesOnly)
    }

    @Test func transform_whenFaceIsUprightAndLarger_thenScalesDownWithoutNotableRotation() throws {
        let detected = FacePoints(leftEye: CGPoint(x: 100, y: 200), rightEye: CGPoint(x: 300, y: 200))
        let transform = try #require(FaceAlignment.transform(from: detected, outputSize: 112))
        #expect(abs(transform.scale - 35.2377 / 200) < 1e-4)
        #expect(abs(transform.rotation) < 0.01)
    }

    @Test func transform_whenAllFivePointsFitTheTemplate_thenEveryPointMapsExactly() throws {
        let detected = placed(reference)
        let transform = try #require(FaceAlignment.transform(from: detected, outputSize: 112))
        #expect(close(transform.apply(detected.leftEye), reference.leftEye))
        #expect(close(transform.apply(try #require(detected.nose)), try #require(reference.nose)))
        #expect(close(transform.apply(try #require(detected.rightMouth)), try #require(reference.rightMouth)))
        #expect(abs(transform.scale - 0.25) < 1e-9)
        #expect(abs(transform.rotation + radians(10)) < 1e-9)
    }

    @Test func transform_whenFivePointsDisagreeWithTheTemplate_thenUsesAllOfThem() throws {
        var detected = placed(reference)
        detected.nose = place(CGPoint(x: 56, y: 85))
        let five = try #require(FaceAlignment.transform(from: detected, outputSize: 112))
        let eyesOnly = try #require(
            FaceAlignment.transform(from: FacePoints(leftEye: detected.leftEye, rightEye: detected.rightEye), outputSize: 112)
        )
        #expect(five != eyesOnly)
        #expect(!close(five.apply(detected.leftEye), reference.leftEye, tolerance: 0.1))
        #expect(close(eyesOnly.apply(detected.leftEye), reference.leftEye))
    }

    @Test func transform_whenInputUnusable_thenNil() {
        let point = CGPoint(x: 5, y: 5)
        #expect(FaceAlignment.transform(from: FacePoints(leftEye: point, rightEye: point), outputSize: 112) == nil)
        #expect(FaceAlignment.transform(from: FacePoints(leftEye: point, rightEye: CGPoint(x: Double.nan, y: 0)), outputSize: 112) == nil)
        #expect(FaceAlignment.transform(from: FacePoints(leftEye: point, rightEye: CGPoint(x: 50, y: 5)), outputSize: 0) == nil)
    }

    @Test func affineTransform_whenAppliedToAPoint_thenMatchesApply() {
        let transform = SimilarityTransform(a: 0.5, b: 0.25, tx: 3, ty: -2)
        let point = CGPoint(x: 12, y: 34)
        #expect(close(point.applying(transform.affineTransform), transform.apply(point)))
    }

    @Test func bottomLeftOriginTransform_whenPointGivenWithYUp_thenLandsWhereTopLeftMappingPutsIt() {
        let transform = SimilarityTransform(a: 0.5, b: 0.1, tx: 3, ty: -2)
        let flipped = FaceAlignment.bottomLeftOriginTransform(transform, sourceHeight: 720, outputSize: 112)
        let topLeftPoint = CGPoint(x: 200, y: 150)
        let expected = transform.apply(topLeftPoint)
        let actual = CGPoint(x: topLeftPoint.x, y: 720 - topLeftPoint.y).applying(flipped)
        #expect(close(actual, CGPoint(x: expected.x, y: 112 - expected.y)))
    }
}

@Suite struct FacePointsTests {
    private func outline(around center: CGPoint) -> [CGPoint] {
        [
            CGPoint(x: center.x - 10, y: center.y), CGPoint(x: center.x, y: center.y - 3),
            CGPoint(x: center.x + 10, y: center.y), CGPoint(x: center.x, y: center.y + 3),
        ]
    }

    private let noseCrest = [CGPoint(x: 150, y: 105), CGPoint(x: 150, y: 130), CGPoint(x: 151, y: 160)]
    private let lips = [
        CGPoint(x: 120, y: 200), CGPoint(x: 150, y: 192), CGPoint(x: 181, y: 201), CGPoint(x: 150, y: 212),
    ]

    @Test func derived_whenAllLandmarksPresent_thenFivePointsInImageOrder() throws {
        let points = try #require(FacePoints.derived(
            eyeOutlines: (outline(around: CGPoint(x: 200, y: 100)), outline(around: CGPoint(x: 100, y: 102))),
            noseCrest: noseCrest,
            outerLips: lips
        ))
        #expect(points.leftEye == CGPoint(x: 100, y: 102))
        #expect(points.rightEye == CGPoint(x: 200, y: 100))
        #expect(points.nose == CGPoint(x: 151, y: 160))
        #expect(points.leftMouth == CGPoint(x: 120, y: 200))
        #expect(points.rightMouth == CGPoint(x: 181, y: 201))
        #expect(points.allFive?.count == 5)
    }

    @Test func derived_whenEyeOutlineMissing_thenUsesPupil() throws {
        let points = try #require(FacePoints.derived(
            eyeOutlines: ([], outline(around: CGPoint(x: 200, y: 100))),
            pupils: (CGPoint(x: 98, y: 101), nil)
        ))
        #expect(points.leftEye == CGPoint(x: 98, y: 101))
        #expect(points.rightEye == CGPoint(x: 200, y: 100))
    }

    @Test func derived_whenNoseOrLipsMissing_thenThosePointsAreNil() throws {
        let points = try #require(FacePoints.derived(
            eyeOutlines: (outline(around: CGPoint(x: 100, y: 100)), outline(around: CGPoint(x: 200, y: 100))),
            outerLips: [CGPoint(x: 150, y: 200)]
        ))
        #expect(points.nose == nil)
        #expect(points.leftMouth == nil)
        #expect(points.rightMouth == nil)
        #expect(points.allFive == nil)
    }

    @Test func derived_whenAnEyeCannotBeLocated_thenNil() {
        #expect(FacePoints.derived(eyeOutlines: ([], outline(around: .zero))) == nil)
        #expect(FacePoints.derived(eyeOutlines: (outline(around: .zero), []), pupils: (CGPoint(x: 1, y: 1), nil)) == nil)
    }

    /// A face looking at the camera, in upright image pixels with a top-left origin. Returned
    /// as the landmark groups a detector reports: the person's own left eye first.
    private func face(mirrored: Bool, rollDegrees: Double) -> (eyes: ([CGPoint], [CGPoint]), nose: [CGPoint], lips: [CGPoint]) {
        func place(_ point: CGPoint) -> CGPoint {
            let x = mirrored ? 1000 - point.x : point.x
            let angle = radians(rollDegrees)
            let dx = x - 500, dy = point.y - 400
            return CGPoint(x: 500 + dx * cos(angle) - dy * sin(angle), y: 400 + dx * sin(angle) + dy * cos(angle))
        }
        // Unmirrored, the person's left eye is on the image's right.
        let personLeftEye = outline(around: CGPoint(x: 560, y: 340)).map(place)
        let personRightEye = outline(around: CGPoint(x: 440, y: 340)).map(place)
        let crest = [CGPoint(x: 500, y: 345), CGPoint(x: 500, y: 380), CGPoint(x: 500, y: 410)].map(place)
        let lips = [CGPoint(x: 455, y: 470), CGPoint(x: 500, y: 460), CGPoint(x: 545, y: 470), CGPoint(x: 500, y: 485)].map(place)
        return ((personLeftEye, personRightEye), crest, lips)
    }

    @Test(arguments: [(false, 0.0), (true, 0.0), (false, 30.0), (true, -30.0), (true, 30.0)])
    func derived_whenImageIsMirroredOrRolled_thenCropIsUprightAndNotFlipped(mirrored: Bool, roll: Double) throws {
        let landmarks = face(mirrored: mirrored, rollDegrees: roll)
        let detected = try #require(FacePoints.derived(eyeOutlines: landmarks.eyes, noseCrest: landmarks.nose, outerLips: landmarks.lips))
        let transform = try #require(FaceAlignment.transform(from: detected, outputSize: 112))
        let reference = FaceAlignment.referencePoints(outputSize: 112)

        let leftEye = transform.apply(detected.leftEye), rightEye = transform.apply(detected.rightEye)
        let nose = transform.apply(try #require(detected.nose))
        let leftMouth = transform.apply(try #require(detected.leftMouth)), rightMouth = transform.apply(try #require(detected.rightMouth))
        // Eyes above nose above mouth, and the left-side points stay on the left.
        #expect(max(leftEye.y, rightEye.y) < nose.y)
        #expect(nose.y < min(leftMouth.y, rightMouth.y))
        #expect(leftEye.x < rightEye.x)
        #expect(leftMouth.x < rightMouth.x)
        // Every point lands near its slot in the template.
        #expect(hypot(leftEye.x - reference.leftEye.x, leftEye.y - reference.leftEye.y) < 6)
        #expect(hypot(rightEye.x - reference.rightEye.x, rightEye.y - reference.rightEye.y) < 6)
        #expect(hypot(leftMouth.x - 41.5493, leftMouth.y - 92.3655) < 6)
        // A similarity transform has no reflection, and it undoes the roll.
        #expect(transform.a * transform.a + transform.b * transform.b > 0)
        #expect(abs(transform.rotation + radians(roll)) < radians(4))
    }

    @Test func derived_whenImageIsMirrored_thenSmallerXEyeIsLeftWhateverTheLandmarkOrder() throws {
        let plain = face(mirrored: false, rollDegrees: 0)
        let mirrored = face(mirrored: true, rollDegrees: 0)
        let first = try #require(FacePoints.derived(eyeOutlines: plain.eyes))
        let second = try #require(FacePoints.derived(eyeOutlines: mirrored.eyes))
        #expect(first.leftEye.x < first.rightEye.x)
        #expect(second.leftEye.x < second.rightEye.x)
        #expect(first.leftEye == second.leftEye)
    }

    @Test func derived_whenHeadIsRolled_thenMouthCornersFollowTheEyeLine() throws {
        // Eyes on a vertical line: the face is rolled by 90 degrees, so "along the eyes" is y.
        let points = try #require(FacePoints.derived(
            eyeOutlines: (outline(around: CGPoint(x: 100, y: 100)), outline(around: CGPoint(x: 100.5, y: 200))),
            outerLips: [CGPoint(x: 10, y: 120), CGPoint(x: 0, y: 150), CGPoint(x: 12, y: 180), CGPoint(x: 20, y: 150)]
        ))
        #expect(points.leftMouth == CGPoint(x: 10, y: 120))
        #expect(points.rightMouth == CGPoint(x: 12, y: 180))
    }
}

@Suite struct EyeGeometryTests {
    private let rectangle = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 3), CGPoint(x: 0, y: 3)]

    @Test func openness_whenOutlineIsADiamond_thenHeightOverWidth() throws {
        let diamond = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 1.5), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: -1.5)]
        #expect(abs(try #require(EyeGeometry.openness(outline: diamond)) - 0.3) < 1e-6)
    }

    @Test func openness_whenOutlineIsRotated_thenUnchanged() throws {
        let diamond = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 1.5), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: -1.5)]
        let angle = radians(30)
        let rotated = diamond.map { CGPoint(x: $0.x * cos(angle) - $0.y * sin(angle), y: $0.x * sin(angle) + $0.y * cos(angle)) }
        #expect(abs(try #require(EyeGeometry.openness(outline: rotated)) - 0.3) < 1e-6)
    }

    @Test func openness_whenOutlineUnusable_thenNil() {
        #expect(EyeGeometry.openness(outline: Array(rectangle.prefix(2))) == nil)
        #expect(EyeGeometry.openness(outline: [CGPoint.zero, .zero, .zero]) == nil)
    }

    @Test func meanOpenness_whenSomeOutlinesUsable_thenAveragesThose() throws {
        let diamond = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 1), CGPoint(x: 10, y: 0), CGPoint(x: 5, y: -1)]
        let closed = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)]
        #expect(abs(try #require(EyeGeometry.meanOpenness(outlines: [diamond, closed, []])) - 0.1) < 1e-6)
        #expect(EyeGeometry.meanOpenness(outlines: [[]]) == nil)
    }

    @Test func centroid_whenPointsGiven_thenMean() {
        #expect(EyeGeometry.centroid(of: rectangle) == CGPoint(x: 5, y: 1.5))
        #expect(EyeGeometry.centroid(of: []) == nil)
    }
}

@Suite struct PixelTensorEncoderTests {
    /// Two pixels in one row with two bytes of row padding: pure red, then (R 0, G 51, B 102).
    private let bytes: [UInt8] = [0, 0, 255, 255, 102, 51, 0, 255, 9, 9]

    private func encode(_ preprocessing: EmbedderPreprocessing, _ layout: TensorLayout, width: Int = 2, height: Int = 1, bytesPerRow: Int = 10) -> [Float]? {
        bytes.withUnsafeBytes {
            PixelTensorEncoder.encode(bgra: $0, width: width, height: height, bytesPerRow: bytesPerRow, preprocessing: preprocessing, layout: layout)
        }
    }

    @Test func encode_whenRawChannelsFirst_thenPlanesAreRedGreenBlue() {
        #expect(encode(.raw, .channelsFirst) == [255, 0, 0, 51, 0, 102])
    }

    @Test func encode_whenRawChannelsLast_thenPixelsAreInterleaved() {
        #expect(encode(.raw, .channelsLast) == [255, 0, 0, 0, 51, 102])
    }

    @Test func encode_whenSignedUnit_thenValuesSpanMinusOneToOne() throws {
        let tensor = try #require(encode(.signedUnit, .channelsFirst))
        #expect(abs(tensor[0] - 1) < 1e-6)
        #expect(abs(tensor[1] + 1) < 1e-6)
        #expect(abs(tensor[3] - (51 / 127.5 - 1)) < 1e-6)
    }

    @Test func encode_whenUnitRange_thenValuesSpanZeroToOne() throws {
        let tensor = try #require(encode(.unitRange, .channelsLast))
        #expect(abs(tensor[0] - 1) < 1e-6)
        #expect(abs(tensor[4] - 0.2) < 1e-6)
    }

    @Test func encode_whenBlueGreenRedOrder_thenChannelsAndStatisticsFollow() throws {
        var preprocessing = EmbedderPreprocessing.imageNet
        preprocessing.channelOrder = .bgr
        let tensor = try #require(encode(preprocessing, .channelsLast))
        // First pixel is pure red, so its last channel carries red with the red statistics.
        #expect(abs(tensor[0] - (0 - 0.406) / 0.225) < 1e-5)
        #expect(abs(tensor[2] - (1 - 0.485) / 0.229) < 1e-5)
    }

    @Test func encode_whenGeometryOrStatisticsInvalid_thenNil() {
        #expect(encode(.raw, .channelsFirst, width: 0) == nil)
        #expect(encode(.raw, .channelsFirst, height: 0) == nil)
        #expect(encode(.raw, .channelsFirst, bytesPerRow: 4) == nil)
        #expect(encode(.raw, .channelsFirst, height: 2) == nil)
        #expect(encode(EmbedderPreprocessing(scale: 1, mean: [0], deviation: [1, 1, 1]), .channelsFirst) == nil)
        #expect(encode(EmbedderPreprocessing(scale: 1, mean: [0, 0, 0], deviation: [1, 1]), .channelsFirst) == nil)
        #expect(encode(EmbedderPreprocessing(scale: 1, mean: [0, 0, 0], deviation: [1, 0, 1]), .channelsFirst) == nil)
    }
}

@Suite struct FrameThrottleTests {
    @Test func shouldProcess_whenFramesArriveFasterThanTheRate_thenDropsTheExtraOnes() {
        var throttle = FrameThrottle(framesPerSecond: 8)
        #expect(throttle.minimumInterval == 0.125)
        #expect(throttle.shouldProcess(at: 10) == true)
        #expect(throttle.shouldProcess(at: 10.05) == false)
        #expect(throttle.shouldProcess(at: 10.1) == false)
        #expect(throttle.shouldProcess(at: 10.13) == true)
    }

    @Test func setRate_whenRateDrops_thenFramesAreSpacedFartherApart() {
        var throttle = FrameThrottle(framesPerSecond: 8)
        #expect(throttle.shouldProcess(at: 10) == true)
        throttle.setRate(framesPerSecond: 2)
        #expect(throttle.shouldProcess(at: 10.2) == false)
        #expect(throttle.shouldProcess(at: 10.5) == true)
    }

    @Test func shouldProcess_whenClockGoesBackward_thenLetsTheFrameThrough() {
        var throttle = FrameThrottle(framesPerSecond: 8)
        #expect(throttle.shouldProcess(at: 10) == true)
        #expect(throttle.shouldProcess(at: 2) == true)
    }

    @Test func shouldProcess_whenRateIsNotPositive_thenLetsEveryFrameThrough() {
        var throttle = FrameThrottle(framesPerSecond: 0)
        #expect(throttle.shouldProcess(at: 1) == true)
        #expect(throttle.shouldProcess(at: 1) == true)
    }
}

@Suite struct FrameRateGovernorTests {
    @Test func update_whenFaceAppears_thenActive() {
        var governor = FrameRateGovernor()
        #expect(governor.mode == .idle)
        #expect(governor.update(facePresent: false, showsPreview: false, at: 0) == nil)
        #expect(governor.update(facePresent: true, showsPreview: false, at: 1) == .active)
        #expect(governor.update(facePresent: true, showsPreview: false, at: 2) == nil)
    }

    @Test func update_whenFaceGoneLongerThanTheHold_thenIdle() {
        var governor = FrameRateGovernor(policy: FrameRatePolicy(activeHold: 10))
        _ = governor.update(facePresent: true, showsPreview: false, at: 1)
        #expect(governor.update(facePresent: false, showsPreview: false, at: 10.5) == nil)
        #expect(governor.update(facePresent: false, showsPreview: false, at: 11.5) == .idle)
    }

    @Test func update_whenPreviewIsOnScreen_thenPreviewRateWithOrWithoutAFace() {
        var governor = FrameRateGovernor()
        #expect(governor.update(facePresent: false, showsPreview: true, at: 0) == .preview)
        #expect(governor.update(facePresent: true, showsPreview: true, at: 1) == nil)
        #expect(governor.mode == .preview)
    }

    @Test func update_whenPreviewCloses_thenReturnsToWhatFacesAskFor() {
        var withFace = FrameRateGovernor()
        _ = withFace.update(facePresent: true, showsPreview: true, at: 0)
        #expect(withFace.update(facePresent: true, showsPreview: false, at: 1) == .active)
        var withoutFace = FrameRateGovernor()
        _ = withoutFace.update(facePresent: false, showsPreview: true, at: 0)
        #expect(withoutFace.update(facePresent: false, showsPreview: false, at: 1) == .idle)
    }

    @Test func update_whenClockRestarts_thenOldFaceDoesNotKeepItActive() {
        var governor = FrameRateGovernor()
        _ = governor.update(facePresent: true, showsPreview: false, at: 100)
        #expect(governor.update(facePresent: false, showsPreview: false, at: 1) == .idle)
    }

    @Test func reset_whenActive_thenIdle() {
        var governor = FrameRateGovernor()
        _ = governor.update(facePresent: true, showsPreview: false, at: 1)
        governor.reset()
        #expect(governor.mode == .idle)
    }

    @Test func policy_whenModeChanges_thenRatesFollow() {
        let policy = FrameRatePolicy()
        #expect(policy.captureRate(in: .idle) == 5)
        #expect(policy.captureRate(in: .active) == 15)
        #expect(policy.captureRate(in: .preview) == 30)
        #expect(policy.analysisRate(in: .idle) == 2)
        #expect(policy.analysisRate(in: .active) == 8)
        #expect(policy.analysisRate(in: .preview) == 8)
        #expect(policy.highestCaptureRate == 30)
    }
}

@Suite struct CameraDemandTests {
    private func plan(requested: Bool = false, enabled: Bool = false, enrolling: Bool = false, mirror: Bool = false, foreground: Bool = true) -> CameraPlan {
        CameraDemand.plan(
            requested: requested, recognitionEnabled: enabled, isEnrolling: enrolling, isMirrorActive: mirror, isForeground: foreground
        )
    }

    @Test func plan_whenMirrorOnAndRecognitionOff_thenCameraRunsWithoutAnalysis() {
        #expect(plan(requested: true, enabled: false, mirror: true) == CameraPlan(runsCamera: true, analyzesFrames: false, showsPreview: true))
        #expect(plan(requested: false, enabled: true, mirror: true) == CameraPlan(runsCamera: true, analyzesFrames: false, showsPreview: true))
    }

    @Test func plan_whenMirrorOffAndRecognitionOff_thenCameraStops() {
        #expect(plan(requested: true, enabled: false, mirror: false) == .stopped)
        #expect(plan(requested: false, enabled: true, mirror: false) == .stopped)
    }

    @Test func plan_whenInBackground_thenCameraStopsWhateverElseIsWanted() {
        #expect(plan(requested: true, enabled: true, enrolling: true, mirror: true, foreground: false) == .stopped)
        #expect(plan(mirror: true, foreground: false) == .stopped)
        #expect(plan(requested: true, enabled: true, foreground: false) == .stopped)
    }

    @Test func plan_whenRecognitionRunsAlone_thenAnalysisWithoutPreviewRate() {
        #expect(plan(requested: true, enabled: true) == CameraPlan(runsCamera: true, analyzesFrames: true, showsPreview: false))
    }

    @Test func plan_whenMirrorOnAndRecognitionOn_thenAnalysisAtPreviewRate() {
        #expect(plan(requested: true, enabled: true, mirror: true) == CameraPlan(runsCamera: true, analyzesFrames: true, showsPreview: true))
    }

    @Test func plan_whenEnrollingWithRecognitionOff_thenAnalysisAtPreviewRate() {
        #expect(plan(enrolling: true) == CameraPlan(runsCamera: true, analyzesFrames: true, showsPreview: true))
    }
}

@Suite struct FaceViewerPositionTests {
    @Test func init_whenBoxIsOnTheCameraImagesRight_thenMirrorPositionIsOnTheLeft() {
        // The person's own left is the right side of the unmirrored camera image.
        let position = FaceViewerPosition(uprightCameraBox: CGRect(x: 0.7, y: 0.6, width: 0.2, height: 0.2))
        #expect(abs(position.x - 0.2) < 1e-9)
        #expect(abs(position.y - 0.3) < 1e-9)
    }

    @Test func init_whenBoxIsCentered_thenPositionIsCentered() {
        #expect(FaceViewerPosition(uprightCameraBox: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)) == FaceViewerPosition(x: 0.5, y: 0.5))
    }

    @Test func init_whenValuesOutOfRange_thenClamped() {
        #expect(FaceViewerPosition(x: -0.2, y: 1.4) == FaceViewerPosition(x: 0, y: 1))
        #expect(FaceViewerPosition(x: .nan, y: .nan) == FaceViewerPosition(x: 0.5, y: 0.5))
        #expect(FaceViewerPosition(uprightCameraBox: CGRect(x: 1.2, y: -0.5, width: 0.2, height: 0.2)) == FaceViewerPosition(x: 0, y: 1))
    }
}

@Suite struct FacePositionSmootherTests {
    @Test func update_whenFirstFaceAppears_thenReportsItAtOnce() {
        var smoother = FacePositionSmoother()
        #expect(smoother.position == nil)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.3, y: 0.6)) == true)
        #expect(smoother.position == FaceViewerPosition(x: 0.3, y: 0.6))
    }

    @Test func update_whenFaceJumps_thenPositionFollowsPartWayEachFrame() throws {
        var smoother = FacePositionSmoother(responsiveness: 0.5, minimumChange: 0.01)
        smoother.update(with: FaceViewerPosition(x: 0.2, y: 0.5))
        #expect(smoother.update(with: FaceViewerPosition(x: 0.6, y: 0.5)) == true)
        #expect(abs(try #require(smoother.position).x - 0.4) < 1e-9)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.6, y: 0.5)) == true)
        #expect(abs(try #require(smoother.position).x - 0.5) < 1e-9)
    }

    @Test func update_whenFaceJitters_thenReportedPositionDoesNotChange() {
        var smoother = FacePositionSmoother(responsiveness: 0.35, minimumChange: 0.01)
        smoother.update(with: FaceViewerPosition(x: 0.5, y: 0.5))
        for offset in [0.01, -0.01, 0.012, -0.008, 0.01, -0.012] {
            #expect(smoother.update(with: FaceViewerPosition(x: 0.5 + offset, y: 0.5 - offset)) == false)
        }
        #expect(smoother.position == FaceViewerPosition(x: 0.5, y: 0.5))
    }

    @Test func update_whenSmallMovesAddUp_thenReportedOnceTheyPassTheBound() throws {
        var smoother = FacePositionSmoother(responsiveness: 1, minimumChange: 0.05)
        smoother.update(with: FaceViewerPosition(x: 0.5, y: 0.5))
        #expect(smoother.update(with: FaceViewerPosition(x: 0.52, y: 0.5)) == false)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.54, y: 0.5)) == false)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.56, y: 0.5)) == true)
        #expect(abs(try #require(smoother.position).x - 0.56) < 1e-9)
    }

    @Test func update_whenFaceDropsOutBriefly_thenPositionHolds() {
        var smoother = FacePositionSmoother(missesToClear: 3)
        smoother.update(with: FaceViewerPosition(x: 0.3, y: 0.6))
        #expect(smoother.update(with: nil) == false)
        #expect(smoother.update(with: nil) == false)
        #expect(smoother.position == FaceViewerPosition(x: 0.3, y: 0.6))
        #expect(smoother.update(with: FaceViewerPosition(x: 0.3, y: 0.6)) == false)
        #expect(smoother.update(with: nil) == false)
    }

    @Test func update_whenFaceGoneForSeveralFrames_thenPositionClearsOnce() {
        var smoother = FacePositionSmoother(missesToClear: 3)
        smoother.update(with: FaceViewerPosition(x: 0.3, y: 0.6))
        smoother.update(with: nil)
        smoother.update(with: nil)
        #expect(smoother.update(with: nil) == true)
        #expect(smoother.position == nil)
        #expect(smoother.update(with: nil) == false)
    }

    @Test func update_whenFaceReturnsAfterClearing_thenStartsFromTheNewPlace() {
        var smoother = FacePositionSmoother(missesToClear: 1)
        smoother.update(with: FaceViewerPosition(x: 0.1, y: 0.1))
        smoother.update(with: nil)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.9, y: 0.9)) == true)
        #expect(smoother.position == FaceViewerPosition(x: 0.9, y: 0.9))
    }

    @Test func reset_whenFacePresent_thenClearsAtOnce() {
        var smoother = FacePositionSmoother()
        smoother.update(with: FaceViewerPosition(x: 0.3, y: 0.6))
        smoother.reset()
        #expect(smoother.position == nil)
        #expect(smoother.update(with: FaceViewerPosition(x: 0.7, y: 0.2)) == true)
        #expect(smoother.position == FaceViewerPosition(x: 0.7, y: 0.2))
    }

    @Test func init_whenValuesOutOfRange_thenClamped() {
        let smoother = FacePositionSmoother(responsiveness: 5, minimumChange: -1, missesToClear: 0)
        #expect(smoother.responsiveness == 1)
        #expect(smoother.minimumChange == 0)
        #expect(smoother.missesToClear == 1)
        #expect(FacePositionSmoother(responsiveness: 0).responsiveness == 0.01)
    }
}

@Suite struct EmbedderModelProfileTests {
    @Test func resolve_whenShapeIsTheSFaceContract_thenSFaceProfile() {
        let profile = EmbedderModelProfile.resolve(for: .init(
            inputIsImage: true, inputWidth: 112, inputHeight: 112, outputName: "embedding", outputDimension: 128
        ))
        #expect(profile == .sFace)
        #expect(profile.matchPolicy.minimumSimilarity == 0.363)
        #expect(profile.matchPolicy.minimumMargin > 0)
        #expect(profile.modelID(modelName: "FaceEmbedder", dimension: 128) == "sface.FaceEmbedder.128")
    }

    @Test(arguments: [
        EmbedderModelShape(inputIsImage: false, inputWidth: 112, inputHeight: 112, outputName: "embedding", outputDimension: 128),
        EmbedderModelShape(inputIsImage: true, inputWidth: 160, inputHeight: 160, outputName: "embedding", outputDimension: 128),
        EmbedderModelShape(inputIsImage: true, inputWidth: 112, inputHeight: 112, outputName: "output", outputDimension: 128),
        EmbedderModelShape(inputIsImage: true, inputWidth: 112, inputHeight: 112, outputName: "embedding", outputDimension: 512),
    ])
    func resolve_whenShapeDiffersFromSFace_thenGenericProfile(shape: EmbedderModelShape) {
        let profile = EmbedderModelProfile.resolve(for: shape)
        #expect(profile == .generic)
        #expect(profile.matchPolicy == .conservativeDefault)
        #expect(profile.modelID(modelName: "FaceEmbedder", dimension: shape.outputDimension).hasPrefix("coreml.FaceEmbedder."))
    }

    @Test func init_whenCustomProfile_thenKeepsValues() {
        let profile = EmbedderModelProfile(family: "custom", matchPolicy: .sFace, preprocessing: .unitRange)
        #expect(profile.family == "custom")
        #expect(profile.preprocessing == .unitRange)
    }
}
