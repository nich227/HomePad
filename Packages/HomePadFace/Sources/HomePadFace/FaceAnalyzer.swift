import AVFoundation
import CoreImage
import Foundation
import HomePadFaceCore
import Vision

/// What Vision and the depth map say about one frame. The crop is the only image data that
/// leaves the analyzer, and it goes straight to the embedder.
struct FaceFrameAnalysis {
    struct Face {
        let sizeFraction: Double
        let pose: HeadPose
        let captureQuality: Float
        let eyeOpenness: Float?
        let depth: FaceDepthStatistics?
        let alignedCrop: CVPixelBuffer?
        let viewerPosition: FaceViewerPosition
        let distance: FaceDistanceEstimate?
    }

    let prominentFaceCount: Int
    let face: Face?

    static var empty: FaceFrameAnalysis { FaceFrameAnalysis(prominentFaceCount: 0, face: nil) }
}

/// Finds the primary face in a frame and measures it.
public struct FaceAnalyzer: Sendable {
    public struct Configuration: Sendable {
        public var selector: PrimaryFaceSelector
        /// Depth is sampled on a grid of this many points per side across the face box.
        public var depthGridSide: Int
        /// Multipliers that turn Vision's yaw and pitch into the convention of `HeadPose`
        /// (positive yaw is the person's left, positive pitch is up). Vision reports pitch as
        /// positive when nodding down. Its yaw sign for an unmirrored front camera is assumed
        /// here and should be checked on a device: if the enrollment ring fills on the wrong
        /// side, flip `yawSign`.
        public var yawSign: Double
        public var pitchSign: Double
        public var distance: FaceDistanceModel

        public init(
            selector: PrimaryFaceSelector = PrimaryFaceSelector(),
            depthGridSide: Int = 24,
            yawSign: Double = 1,
            pitchSign: Double = -1,
            distance: FaceDistanceModel = FaceDistanceModel()
        ) {
            self.selector = selector
            self.depthGridSide = depthGridSide
            self.yawSign = yawSign
            self.pitchSign = pitchSign
            self.distance = distance
        }
    }

    private let configuration: Configuration
    private let context: CIContext

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        // No intermediate caching: every frame is different, and face pixels should not linger.
        self.context = CIContext(options: [.cacheIntermediates: false])
    }

    func analyze(_ frame: CameraFrame, cropSide: Int) -> FaceFrameAnalysis {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: frame.orientation)
        let rectangles = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([rectangles])) != nil, let faces = rectangles.results, !faces.isEmpty else {
            return .empty
        }
        guard let selection = configuration.selector.select(from: faces.map(\.boundingBox)) else {
            return .empty
        }
        let primary = faces[selection.index]

        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = [primary]
        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = [primary]
        // Either request may fail on a hard frame. The face is still reported, without a crop.
        _ = try? handler.perform([landmarks, quality])

        let size = Self.uprightSize(of: frame.pixelBuffer, orientation: frame.orientation)
        let box = primary.boundingBox
        let regions = landmarks.results?.first?.landmarks
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            // Vision's origin is the bottom-left corner. The alignment math uses the top-left.
            (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: size.height - $0.y) }
        }
        let eyeOutlines = (points(regions?.leftEye), points(regions?.rightEye))

        var crop: CVPixelBuffer?
        if let detected = FacePoints.derived(
            eyeOutlines: eyeOutlines,
            pupils: (points(regions?.leftPupil).first, points(regions?.rightPupil).first),
            noseCrest: points(regions?.noseCrest),
            outerLips: points(regions?.outerLips)
        ), let transform = FaceAlignment.transform(from: detected, outputSize: Double(cropSide)) {
            crop = alignedCrop(of: frame, uprightHeight: size.height, transform: transform, side: cropSide)
        }

        let depth = frame.depthData.flatMap { depthStatistics(of: $0, orientation: frame.orientation, faceBox: box) }
        let face = FaceFrameAnalysis.Face(
            sizeFraction: ProximityEstimator.sizeFraction(
                normalizedHeight: box.height,
                frameWidth: size.width,
                frameHeight: size.height
            ),
            pose: HeadPose(
                yaw: (primary.yaw?.doubleValue ?? 0) * configuration.yawSign,
                pitch: (primary.pitch?.doubleValue ?? 0) * configuration.pitchSign,
                roll: primary.roll?.doubleValue ?? 0
            ),
            captureQuality: quality.results?.first?.faceCaptureQuality ?? 0,
            eyeOpenness: EyeGeometry.meanOpenness(outlines: [eyeOutlines.0, eyeOutlines.1]),
            depth: depth,
            alignedCrop: crop,
            // Vision's box is in the upright, unmirrored camera image with a bottom-left origin.
            viewerPosition: FaceViewerPosition(uprightCameraBox: box),
            distance: configuration.distance.estimate(
                depth: depth,
                faceSizeMeters: configuration.distance.metersFromFaceSize(
                    normalizedFaceHeight: box.height,
                    frameWidth: size.width,
                    frameHeight: size.height,
                    fieldOfViewDegrees: frame.fieldOfViewDegrees
                )
            )
        )
        return FaceFrameAnalysis(prominentFaceCount: selection.prominentFaceCount, face: face)
    }

    private static func uprightSize(of buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: return CGSize(width: height, height: width)
        default: return CGSize(width: width, height: height)
        }
    }

    private func alignedCrop(
        of frame: CameraFrame,
        uprightHeight: Double,
        transform: SimilarityTransform,
        side: Int
    ) -> CVPixelBuffer? {
        guard let output = PixelBufferFactory.makeBGRA(side: side) else { return nil }
        let upright = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(frame.orientation)
        let atOrigin = upright.transformed(by: CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY))
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let aligned = atOrigin
            .transformed(by: FaceAlignment.bottomLeftOriginTransform(transform, sourceHeight: uprightHeight, outputSize: Double(side)))
            .cropped(to: bounds)
        context.render(aligned, to: output, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return output
    }

    /// Samples depth on a grid inside the ellipse inscribed in the face box, so hair and
    /// background at the corners of the box do not count.
    private func depthStatistics(
        of depthData: AVDepthData,
        orientation: CGImagePropertyOrientation,
        faceBox: CGRect
    ) -> FaceDepthStatistics? {
        let map = depthData
            .applyingExifOrientation(orientation)
            .converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            .depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)
        let side = max(2, configuration.depthGridSide)
        var samples: [DepthPoint] = []
        samples.reserveCapacity(side * side)
        for row in 0..<side {
            for column in 0..<side {
                let u = (Double(column) + 0.5) / Double(side)
                let v = (Double(row) + 0.5) / Double(side)
                guard hypot(u - 0.5, v - 0.5) <= 0.5 else { continue }
                // `v` runs downward from the top of the box. The box origin is its bottom-left.
                let x = Int((faceBox.minX + u * faceBox.width) * Double(width))
                let y = Int((1 - faceBox.maxY + v * faceBox.height) * Double(height))
                var depth = Float.nan
                if (0..<width).contains(x), (0..<height).contains(y) {
                    depth = base.load(fromByteOffset: y * bytesPerRow + x * MemoryLayout<Float32>.size, as: Float32.self)
                }
                samples.append(DepthPoint(x: Float(u), y: Float(v), depth: depth))
            }
        }
        return FaceDepthStatistics(points: samples)
    }
}

/// Runs analysis and embedding for one frame on the capture queue and reduces the frame to
/// numbers.
struct FaceFrameProcessor: Sendable {
    let analyzer: FaceAnalyzer
    let embedder: any FaceEmbedder
    /// Below this capture quality the embedding would be rejected anyway, so the model is not
    /// run.
    let minimumQualityForEmbedding: Float

    func process(_ frame: CameraFrame) -> FaceFrameObservation {
        let light = SceneLightSample(exposure: frame.exposure, meanLuma: SceneLuma.mean(of: frame.pixelBuffer))
        let analysis = analyzer.analyze(frame, cropSide: embedder.inputSide)
        guard let face = analysis.face else {
            return .empty(at: frame.timestamp, light: light)
        }
        var embedding: FaceEmbedding?
        if face.captureQuality >= minimumQualityForEmbedding, let crop = face.alignedCrop {
            embedding = try? embedder.embedding(forAlignedFace: crop)
        }
        return FaceFrameObservation(
            timestamp: frame.timestamp,
            prominentFaceCount: analysis.prominentFaceCount,
            primary: FaceObservationSample(
                sizeFraction: face.sizeFraction,
                pose: face.pose,
                captureQuality: face.captureQuality,
                embedding: embedding,
                depth: face.depth,
                eyeOpenness: face.eyeOpenness,
                viewerPosition: face.viewerPosition,
                distance: face.distance
            ),
            light: light
        )
    }
}

enum SceneLuma {
    /// Mean brightness of about a thousand luma samples taken on a grid across the frame. The
    /// frame is read in place and not copied. Returns `nil` for a pixel format without an 8-bit
    /// luma plane.
    static func mean(of buffer: CVPixelBuffer, gridSide: Int = 32) -> Double? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let isVideoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard isVideoRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        var sum = 0
        for row in 0..<gridSide {
            let y = (2 * row + 1) * height / (2 * gridSide)
            for column in 0..<gridSide {
                let x = (2 * column + 1) * width / (2 * gridSide)
                sum += Int(base.load(fromByteOffset: y * bytesPerRow + x, as: UInt8.self))
            }
        }
        return SceneBrightness.meanLuma(sum: sum, count: width > 0 && height > 0 ? gridSide * gridSide : 0, isVideoRange: isVideoRange)
    }
}
