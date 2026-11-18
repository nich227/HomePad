import AVFoundation
import Foundation
import HomePadCore
import HomePadFaceCore
import ImageIO

public enum CameraAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    /// Blocked by a device restriction the person cannot change.
    case restricted

    public static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Shows the system camera prompt when the person has not answered it yet.
    public static func request() async -> CameraAuthorization {
        if current == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return current
    }
}

public enum FaceCameraError: Error, Equatable, Sendable {
    case notAuthorized
    case noFrontCamera
    case cannotAddInput
    case cannotAddOutput
}

public enum FaceCameraInterruption: Equatable, Sendable {
    case inBackground
    case inUseByAnotherApp
    /// The device does not allow the camera while several apps share the screen.
    case unavailableWithMultipleForegroundApps
    case systemPressure
    case other

    init(reason: AVCaptureSession.InterruptionReason?) {
        switch reason {
        case .videoDeviceNotAvailableInBackground: self = .inBackground
        case .videoDeviceInUseByAnotherClient: self = .inUseByAnotherApp
        case .videoDeviceNotAvailableWithMultipleForegroundApps: self = .unavailableWithMultipleForegroundApps
        case .videoDeviceNotAvailableDueToSystemPressure: self = .systemPressure
        default: self = .other
        }
    }
}

public enum FaceCameraEvent: Equatable, Sendable {
    case interrupted(FaceCameraInterruption)
    case interruptionEnded
    case runtimeError
}

/// One camera frame. It is valid only during the handler call that receives it and is never
/// stored.
public struct CameraFrame {
    public let pixelBuffer: CVPixelBuffer
    public let depthData: AVDepthData?
    /// Seconds of system uptime when the frame was delivered.
    public let timestamp: TimeInterval
    /// How to turn the buffer upright relative to gravity.
    public let orientation: CGImagePropertyOrientation
    /// The active format's field of view across the frame's longer side, in degrees. 0 when the
    /// device does not report one.
    public let fieldOfViewDegrees: Double
    /// The exposure the device used around this frame.
    public let exposure: CameraExposure?
}

/// Hands the capture session to a preview layer.
public final class FaceCameraPreviewSource: @unchecked Sendable {
    // AVCaptureSession is not marked Sendable. It is configured and started on the capture queue
    // while a preview layer on the main thread displays it, which AVFoundation supports. This
    // box only carries the reference between the two.
    let session = AVCaptureSession()

    init() {}
}

/// Owns the front camera. All capture work, including the frame handler, runs on one serial
/// queue that is also this actor's executor.
public actor FaceCameraPipeline {
    private let queue = DispatchSerialQueue(label: HomePadIdentifiers.bundlePrefix + ".face.camera", qos: .userInitiated)

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    public nonisolated let previewSource = FaceCameraPreviewSource()
    public nonisolated let events: AsyncStream<FaceCameraEvent>

    private let eventContinuation: AsyncStream<FaceCameraEvent>.Continuation
    private let handler: @Sendable (CameraFrame) -> Void
    private let rates: FrameRatePolicy
    private var isConfigured = false
    private var isAnalysisEnabled = true
    private var hasDepth = false
    private var device: AVCaptureDevice?
    private var relay: FrameRelay?
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    // Notification observers stay registered for the life of the process. The app creates one
    // pipeline and keeps it.
    private var observers: [any NSObjectProtocol] = []

    /// - Parameter handler: called on the capture queue for each frame that passes the throttle.
    ///   It must finish its work before returning, because the frame is not valid afterward.
    public init(rates: FrameRatePolicy = FrameRatePolicy(), handler: @escaping @Sendable (CameraFrame) -> Void) {
        self.rates = rates
        self.handler = handler
        (events, eventContinuation) = AsyncStream.makeStream(of: FaceCameraEvent.self, bufferingPolicy: .bufferingNewest(8))
    }

    /// Starts the camera in the idle frame rate mode. Returns whether depth is delivered.
    @discardableResult
    public func start() throws(FaceCameraError) -> Bool {
        guard CameraAuthorization.current == .authorized else { throw .notAuthorized }
        if !isConfigured {
            try configure()
            isConfigured = true
        }
        setMode(.idle)
        if !previewSource.session.isRunning {
            previewSource.session.startRunning()
        }
        return hasDepth
    }

    public func stop() {
        if previewSource.session.isRunning {
            previewSource.session.stopRunning()
        }
    }

    /// Turns the frame handler on or off. While off the camera still runs and feeds the preview,
    /// but no frame reaches the handler.
    public func setAnalysisEnabled(_ enabled: Bool) {
        isAnalysisEnabled = enabled
        relay?.isAnalysisEnabled = enabled
    }

    public func setMode(_ mode: FrameRateMode) {
        relay?.throttle.setRate(framesPerSecond: rates.analysisRate(in: mode))
        applyCaptureRate(rates.captureRate(in: mode))
    }

    // MARK: Configuration

    private func configure() throws(FaceCameraError) {
        let session = previewSource.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        guard let device = trueDepth ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw .noFrontCamera
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw .cannotAddInput
        }
        session.addInput(input)
        selectFormat(of: device, prefersDepth: trueDepth != nil)

        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(video) else { throw .cannotAddOutput }
        session.addOutput(video)

        // Analysis sees the camera's own view. Only the preview layer mirrors. Mirroring one data
        // output and not the other would also put the depth map out of step with the image.
        Self.disableMirroring(on: video.connection(with: .video))

        let relay = FrameRelay(throttle: FrameThrottle(framesPerSecond: rates.analysisRate(in: .idle)), handler: handler)
        relay.isAnalysisEnabled = isAnalysisEnabled
        var depthAttached = false
        if trueDepth != nil {
            let depth = AVCaptureDepthDataOutput()
            if session.canAddOutput(depth) {
                session.addOutput(depth)
                // Unfiltered depth keeps the holes a screen or glossy photo leaves, which the
                // liveness check relies on.
                depth.isFilteringEnabled = false
                depth.alwaysDiscardsLateDepthData = true
                Self.disableMirroring(on: depth.connection(with: .depthData))
                if selectDepthFormat(of: device), depth.connection(with: .depthData) != nil {
                    let synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [video, depth])
                    synchronizer.setDelegate(relay, queue: queue)
                    self.synchronizer = synchronizer
                    depthAttached = true
                } else {
                    session.removeOutput(depth)
                }
            }
        }
        if !depthAttached {
            video.setSampleBufferDelegate(relay, queue: queue)
        }
        // On iPad the camera otherwise stops when the app shares the screen with another app.
        if session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }

        // Center Stage crops and moves the frame to follow people. Distance from face size and
        // the viewer position both need the whole, fixed field of view.
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
        relay.fieldOfViewDegrees = Self.fieldOfView(of: device)
        relay.device = device

        self.device = device
        self.relay = relay
        self.hasDepth = depthAttached
        observeRotation(of: device)
        observeSession(session)
    }

    /// The lens differs between devices and formats, so the field of view is read, not assumed.
    private static func fieldOfView(of device: AVCaptureDevice) -> Double {
        let format = device.activeFormat
        let corrected = device.isGeometricDistortionCorrectionSupported && device.isGeometricDistortionCorrectionEnabled
        return Double(corrected ? format.geometricDistortionCorrectedVideoFieldOfView : format.videoFieldOfView)
    }

    private static func disableMirroring(on connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    private func selectFormat(of device: AVCaptureDevice, prefersDepth: Bool) {
        let candidates = device.formats.map { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return CaptureFormatCandidate(
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                maximumFrameRate: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0,
                supportsDepth: !format.supportedDepthDataFormats.isEmpty
            )
        }
        guard
            let index = CaptureFormatSelector(minimumFrameRate: rates.highestCaptureRate).select(from: candidates, prefersDepth: prefersDepth),
            (try? device.lockForConfiguration()) != nil
        else { return }
        device.activeFormat = device.formats[index]
        device.unlockForConfiguration()
    }

    /// Picks the largest depth map, preferring metric depth over disparity. Returns false when
    /// the active format has no depth.
    private func selectDepthFormat(of device: AVCaptureDevice) -> Bool {
        let preference: [OSType] = [
            kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DepthFloat16,
            kCVPixelFormatType_DisparityFloat32, kCVPixelFormatType_DisparityFloat16,
        ]
        let formats = device.activeFormat.supportedDepthDataFormats
        let ranked = formats.compactMap { format -> (rank: Int, width: Int32, format: AVCaptureDevice.Format)? in
            guard let rank = preference.firstIndex(of: CMFormatDescriptionGetMediaSubType(format.formatDescription)) else {
                return nil
            }
            return (rank, CMVideoFormatDescriptionGetDimensions(format.formatDescription).width, format)
        }
        guard
            let best = ranked.min(by: { ($0.rank, -$0.width) < ($1.rank, -$1.width) }),
            (try? device.lockForConfiguration()) != nil
        else { return false }
        device.activeDepthDataFormat = best.format
        device.unlockForConfiguration()
        return true
    }

    private func applyCaptureRate(_ framesPerSecond: Double) {
        guard let device else { return }
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard
            let lowest = ranges.map(\.minFrameRate).min(),
            let highest = ranges.map(\.maxFrameRate).max(),
            (try? device.lockForConfiguration()) != nil
        else { return }
        let rate = min(max(framesPerSecond, lowest), highest)
        let duration = CMTime(value: 1000, timescale: CMTimeScale((rate * 1000).rounded()))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    private func observeRotation(of device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { await self?.setRotationAngle(angle) }
        }
    }

    private func setRotationAngle(_ angle: CGFloat) {
        relay?.rotationAngle = angle
    }

    private func observeSession(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        let continuation = eventContinuation
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { notification in
                let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                continuation.yield(.interrupted(FaceCameraInterruption(reason: reason)))
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { _ in
                continuation.yield(.interruptionEnded)
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { _ in
                continuation.yield(.runtimeError)
            },
        ]
    }

    /// The rotation angle is clockwise degrees needed to make the buffer upright.
    static func orientation(forRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch Int(angle.rounded()) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }
}

/// Receives frames from AVFoundation. It is created by the pipeline, AVFoundation calls it on the
/// pipeline's queue, and the pipeline changes its state from that same queue, so nothing here is
/// touched from two threads.
private final class FrameRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {
    var throttle: FrameThrottle
    var rotationAngle: CGFloat = 0
    var isAnalysisEnabled = true
    var fieldOfViewDegrees: Double = 0
    var device: AVCaptureDevice?
    private let handler: @Sendable (CameraFrame) -> Void

    init(throttle: FrameThrottle, handler: @escaping @Sendable (CameraFrame) -> Void) {
        self.throttle = throttle
        self.handler = handler
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        deliver(sampleBuffer, nil)
    }

    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        var video: CMSampleBuffer?
        var depth: AVDepthData?
        for output in synchronizer.dataOutputs {
            switch synchronizedDataCollection.synchronizedData(for: output) {
            case let data as AVCaptureSynchronizedSampleBufferData where !data.sampleBufferWasDropped:
                video = data.sampleBuffer
            case let data as AVCaptureSynchronizedDepthData where !data.depthDataWasDropped:
                depth = data.depthData
            default:
                break
            }
        }
        if let video {
            deliver(video, depth)
        }
    }

    private func deliver(_ sampleBuffer: CMSampleBuffer, _ depthData: AVDepthData?) {
        guard isAnalysisEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard throttle.shouldProcess(at: now), let pixelBuffer = sampleBuffer.imageBuffer else { return }
        handler(CameraFrame(
            pixelBuffer: pixelBuffer,
            depthData: depthData,
            timestamp: now,
            orientation: FaceCameraPipeline.orientation(forRotationAngle: rotationAngle),
            fieldOfViewDegrees: fieldOfViewDegrees,
            exposure: device.map { device in
                CameraExposure(
                    iso: Double(device.iso),
                    exposureDuration: device.exposureDuration.seconds,
                    aperture: Double(device.lensAperture),
                    targetOffset: Double(device.exposureTargetOffset)
                )
            }
        ))
    }
}
