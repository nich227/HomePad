import HomePadFace
import HomePadUI
import SwiftUI

/// The hub's Mirror, drawn from the face recognition camera session.
@MainActor
final class SharedMirrorCamera: CameraPreviewService {
    private let faces: FaceRecognitionService

    init(faces: FaceRecognitionService) {
        self.faces = faces
    }

    var state: CameraPreviewState {
        switch faces.cameraState {
        case .running: .running
        case .failed(.notAuthorized): .denied
        case .failed, .interrupted: .unavailable
        case .stopped: .idle
        }
    }

    func start() async {
        await faces.setMirrorActive(true)
    }

    func stop() {
        Task { [faces] in
            await faces.setMirrorActive(false)
        }
    }

    func makePreview() -> AnyView {
        AnyView(faces.makeMirrorPreview())
    }
}
