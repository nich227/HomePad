import Foundation

public enum FrameRateMode: String, Equatable, Sendable {
    /// Nobody is in view. The camera and the analysis run slowly to save power.
    case idle
    /// A face is in view.
    case active
    /// A live preview is on screen (the mirror or an enrollment), so the camera runs at a rate
    /// that looks smooth.
    case preview
}

public struct FrameRatePolicy: Equatable, Sendable {
    /// Frames per second the camera captures.
    public var idleCaptureRate: Double
    public var activeCaptureRate: Double
    public var previewCaptureRate: Double
    /// Frames per second that are analyzed.
    public var idleAnalysisRate: Double
    public var activeAnalysisRate: Double
    /// Seconds to stay active after the last face, so a person who looks away is picked up
    /// again quickly.
    public var activeHold: TimeInterval

    public init(
        idleCaptureRate: Double = 5,
        activeCaptureRate: Double = 15,
        previewCaptureRate: Double = 30,
        idleAnalysisRate: Double = 2,
        activeAnalysisRate: Double = 8,
        activeHold: TimeInterval = 10
    ) {
        self.idleCaptureRate = idleCaptureRate
        self.activeCaptureRate = activeCaptureRate
        self.previewCaptureRate = previewCaptureRate
        self.idleAnalysisRate = idleAnalysisRate
        self.activeAnalysisRate = activeAnalysisRate
        self.activeHold = activeHold
    }

    public func captureRate(in mode: FrameRateMode) -> Double {
        switch mode {
        case .idle: idleCaptureRate
        case .active: activeCaptureRate
        case .preview: previewCaptureRate
        }
    }

    /// A preview needs smooth capture, not denser analysis, so it analyzes at the active rate.
    public func analysisRate(in mode: FrameRateMode) -> Double {
        mode == .idle ? idleAnalysisRate : activeAnalysisRate
    }

    /// The highest rate the camera format has to support.
    public var highestCaptureRate: Double {
        max(idleCaptureRate, activeCaptureRate, previewCaptureRate)
    }
}

/// Decides when the camera may slow down. Timestamps are seconds on a monotonic clock.
public struct FrameRateGovernor: Equatable, Sendable {
    public let policy: FrameRatePolicy
    public private(set) var mode: FrameRateMode = .idle
    private var lastFaceAt: TimeInterval?

    public init(policy: FrameRatePolicy = FrameRatePolicy()) {
        self.policy = policy
    }

    /// Returns the new mode when it changed, otherwise `nil`.
    /// - Parameter showsPreview: a live preview is on screen, with or without a face in view.
    public mutating func update(facePresent: Bool, showsPreview: Bool, at timestamp: TimeInterval) -> FrameRateMode? {
        if facePresent {
            lastFaceAt = timestamp
        }
        let recentFace = lastFaceAt.map { timestamp >= $0 && timestamp - $0 < policy.activeHold } ?? false
        let next: FrameRateMode = showsPreview ? .preview : (recentFace ? .active : .idle)
        guard next != mode else { return nil }
        mode = next
        return next
    }

    public mutating func reset() {
        self = FrameRateGovernor(policy: policy)
    }
}

/// What the camera should be doing right now.
public struct CameraPlan: Equatable, Sendable {
    /// The capture session runs.
    public let runsCamera: Bool
    /// Frames are analyzed for faces. False while only the mirror needs the camera: frames are
    /// then shown and nothing else.
    public let analyzesFrames: Bool
    /// A live preview is on screen and needs a smooth frame rate.
    public let showsPreview: Bool

    public init(runsCamera: Bool, analyzesFrames: Bool, showsPreview: Bool) {
        self.runsCamera = runsCamera
        self.analyzesFrames = analyzesFrames
        self.showsPreview = showsPreview
    }

    public static let stopped = CameraPlan(runsCamera: false, analyzesFrames: false, showsPreview: false)
}

public enum CameraDemand {
    /// - Parameters:
    ///   - requested: the app asked for recognition to run.
    ///   - recognitionEnabled: the user's preference.
    ///   - isEnrolling: an enrollment is on screen. It needs the camera and analysis even when
    ///     recognition is turned off.
    ///   - isMirrorActive: the mirror is on screen. It needs the camera, and by itself no
    ///     analysis.
    ///   - isForeground: the camera never runs in the background.
    public static func plan(
        requested: Bool,
        recognitionEnabled: Bool,
        isEnrolling: Bool,
        isMirrorActive: Bool,
        isForeground: Bool
    ) -> CameraPlan {
        guard isForeground else { return .stopped }
        let analyzes = isEnrolling || (requested && recognitionEnabled)
        return CameraPlan(
            runsCamera: analyzes || isMirrorActive,
            analyzesFrames: analyzes,
            showsPreview: isEnrolling || isMirrorActive
        )
    }
}
