import Foundation
import Testing
@testable import HomePadAnimationsCore

private let previewDirectory = ProcessInfo.processInfo.environment["HOMEPAD_ANIMATION_PREVIEW_DIR"]

/// Writes a sheet of frames per animation for a person to look at. It runs only when
/// HOMEPAD_ANIMATION_PREVIEW_DIR names an output directory.
@MainActor @Suite struct PreviewFrameTests {
    @Test(.enabled(if: previewDirectory != nil), arguments: HomePadAnimation.allCases)
    func writeSheet_whenDirectoryGiven_thenWritesSixFrames(animation: HomePadAnimation) throws {
        let directory = URL(fileURLWithPath: try #require(previewDirectory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let renderer = try AnimationRenderer(animation)
        let frames = try (0...5).map { step in
            try renderer.frame(Double(animation.frameCount) * Double(step) / 5)
        }
        try Bitmap.writeSheet(frames, to: directory.appendingPathComponent("\(animation.rawValue).png"))
    }
}
