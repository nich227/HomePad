import SwiftUI

/// The front camera shown as a mirror: mirrored, filling its frame, upright in every interface
/// orientation. It shows the recognition service's camera, because the device allows only one
/// capture session on the front camera.
///
/// The view does not start the camera. Call `FaceRecognitionService.setMirrorActive(_:)` when it
/// appears and disappears.
public struct FaceMirrorView: View {
    private let service: FaceRecognitionService

    public init(service: FaceRecognitionService) {
        self.service = service
    }

    public var body: some View {
        FaceCameraPreview(source: service.previewSource, isRunning: service.cameraState == .running)
            .accessibilityElement()
            .accessibilityLabel(Text("Mirror"))
            .accessibilityAddTraits(.isImage)
    }
}
