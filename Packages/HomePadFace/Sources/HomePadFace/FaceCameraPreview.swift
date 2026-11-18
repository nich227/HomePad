import AVFoundation
import SwiftUI
import UIKit

/// Live front camera preview. Mirrored like a mirror, which is the system default for the front
/// camera.
struct FaceCameraPreview: UIViewRepresentable {
    let source: FaceCameraPreviewSource
    /// Passed so SwiftUI updates the view when the camera starts and the rotation can be set up.
    let isRunning: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach(source.session)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if isRunning {
            view.followRotation()
        }
    }

    final class PreviewView: UIView {
        private let previewLayer = AVCaptureVideoPreviewLayer()
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        func attach(_ session: AVCaptureSession) {
            previewLayer.session = session
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }

        /// Keeps the preview upright as the device turns. The camera input exists only after the
        /// session is configured, so this is called again once the camera runs.
        func followRotation() {
            guard coordinator == nil, let device = previewLayer.session?.inputs.lazy.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first else {
                return
            }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            // Key-value updates for this property arrive on the main queue.
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                MainActor.assumeIsolated {
                    self?.apply(angle)
                }
            }
        }

        private func apply(_ angle: CGFloat) {
            guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
