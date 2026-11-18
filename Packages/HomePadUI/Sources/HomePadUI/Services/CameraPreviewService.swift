import AVFoundation
import Observation
import SwiftUI
import UIKit

public enum CameraPreviewState: Equatable, Sendable {
    case idle
    case running
    case denied
    case unavailable
}

/// The front camera as a mirror. Behind a protocol so the app can hand in a preview that shares
/// the face recognition camera session instead of opening a second one.
@MainActor
public protocol CameraPreviewService: AnyObject {
    var state: CameraPreviewState { get }
    func start() async
    func stop()
    func makePreview() -> AnyView
}

/// The capture session lives on its own queue. Session calls block, so they stay off the main
/// actor; the box is the only thing that touches the session after setup.
private final class CaptureBox: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "HomePadUI.mirror.capture")
    private var device: AVCaptureDevice?

    var captureDevice: AVCaptureDevice? {
        queue.sync { device }
    }

    func configureAndStart() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if device == nil {
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                          let input = try? AVCaptureDeviceInput(device: camera),
                          session.canAddInput(input) else {
                        continuation.resume(returning: false)
                        return
                    }
                    session.beginConfiguration()
                    if session.isMultitaskingCameraAccessSupported {
                        session.isMultitaskingCameraAccessEnabled = true
                    }
                    session.sessionPreset = .high
                    session.addInput(input)
                    session.commitConfiguration()
                    device = camera
                }
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

@MainActor
@Observable
public final class FrontCameraPreviewService: CameraPreviewService {
    public private(set) var state: CameraPreviewState = .idle
    @ObservationIgnored private let box = CaptureBox()

    public init() {}

    public func start() async {
        guard UsageDescriptions.has("NSCameraUsageDescription") else {
            state = .unavailable
            return
        }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        guard granted else {
            state = .denied
            return
        }
        state = await box.configureAndStart() ? .running : .unavailable
    }

    public func stop() {
        box.stop()
        if state == .running {
            state = .idle
        }
    }

    public func makePreview() -> AnyView {
        AnyView(CapturePreview(session: box.session, device: box.captureDevice))
    }
}

private struct CapturePreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let device {
            view.rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        var rotation: AVCaptureDevice.RotationCoordinator?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class is fixed above, so the fallback is never used.
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }

        /// Layout runs on every rotation and resize, which is when the upright angle changes.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let rotation, let connection = previewLayer.connection else { return }
            let angle = rotation.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}

/// A still stand-in for previews and for devices without a camera.
@MainActor
@Observable
public final class PreviewCameraService: CameraPreviewService {
    public private(set) var state: CameraPreviewState

    public init(state: CameraPreviewState = .running) {
        self.state = state
    }

    public func start() async {}
    public func stop() {}

    public func makePreview() -> AnyView {
        AnyView(
            ZStack {
                LinearGradient(colors: [Color(white: 0.35), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(60)
            }
        )
    }
}
