import Foundation
import HomePadCore
import HomePadFaceCore
import Observation
import SwiftUI
import UIKit

public struct FaceRecognitionConfiguration: Sendable {
    /// Thresholds and timing before the preferences from Settings are applied on top.
    public var engine: RecognitionEngineConfiguration
    public var enrollment: EnrollmentPolicy
    public var frameRates: FrameRatePolicy
    public var analyzer: FaceAnalyzer.Configuration
    /// Faces below this capture quality are not sent to the embedding model.
    public var minimumQualityForEmbedding: Float
    /// Smoothing and thresholds for the room brightness estimate.
    public var ambientLight: AmbientLightPolicy

    public init(
        engine: RecognitionEngineConfiguration = RecognitionEngineConfiguration(),
        enrollment: EnrollmentPolicy = EnrollmentPolicy(),
        frameRates: FrameRatePolicy = FrameRatePolicy(),
        analyzer: FaceAnalyzer.Configuration = FaceAnalyzer.Configuration(),
        minimumQualityForEmbedding: Float = 0.1,
        ambientLight: AmbientLightPolicy = AmbientLightPolicy()
    ) {
        self.ambientLight = ambientLight
        self.engine = engine
        self.enrollment = enrollment
        self.frameRates = frameRates
        self.analyzer = analyzer
        self.minimumQualityForEmbedding = minimumQualityForEmbedding
    }
}

public enum FaceCameraState: Equatable, Sendable {
    case stopped
    case running
    case interrupted(FaceCameraInterruption)
    case failed(FaceCameraError)
}

public enum FaceEnrollmentFailure: Equatable, Sendable {
    case cameraNotAuthorized
    case cameraUnavailable
    /// The face already belongs to this other household member.
    case duplicateFace(UUID)
    case storageFailed(FaceTemplateStoreError)
}

/// What the enrollment screen shows.
public struct FaceEnrollmentStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case starting
        case collecting
        case finished
        case failed(FaceEnrollmentFailure)
    }

    public let profileID: UUID
    public internal(set) var phase: Phase = .starting
    /// 0...1 per head pose.
    public internal(set) var bucketProgress: [HeadPoseBucket: Double] = [:]
    public internal(set) var progress: Double = 0
    /// The pose to ask for next.
    public internal(set) var nextBucket: HeadPoseBucket? = .center
    public internal(set) var issue: EnrollmentIssue?

    var isActive: Bool {
        phase == .starting || phase == .collecting
    }
}

/// Recognizes household members in front of the hub and drives the household session.
///
/// Frames and face crops exist only on the capture queue while one frame is analyzed. This
/// object receives numbers (pose, quality, an embedding, depth statistics), never pixels. Only
/// finished templates are stored, and nothing about faces is logged.
@MainActor
@Observable
public final class FaceRecognitionService {
    public private(set) var cameraAuthorization = CameraAuthorization.current
    public private(set) var cameraState = FaceCameraState.stopped
    /// Whether the active camera delivers depth for the liveness check.
    public private(set) var hasDepthCamera = false
    public private(set) var isFacePresent = false
    /// Center of the primary face as the person would see themselves in a mirror filling the
    /// screen: 0...1 on both axes, origin at the top-left, so a move to the person's own left
    /// moves `x` toward 0. `nil` when no face is present or frames are not being analyzed.
    ///
    /// The position is taken in the camera image after it is turned upright relative to gravity,
    /// then flipped horizontally for the mirror view. That equals the screen's orientation
    /// whenever the interface follows the way the device is held, which is the case for a hub on
    /// a stand. If the interface is locked to a different orientation than the device is held
    /// in, or the device lies flat, the position follows gravity and not the interface.
    ///
    /// It is smoothed, and it changes only when the face has moved noticeably.
    public private(set) var facePosition: FaceViewerPosition?
    public private(set) var lastDecision = RecognitionOutcome.nobody
    /// Which of the three distance zones the primary face is in. `.far` when nobody is in view.
    public private(set) var proximity = Proximity.far
    /// Estimated distance of the primary face, rounded to 5 cm, and whether it came from the
    /// depth camera or from the size of the face. `nil` when no face is in view or the distance
    /// could not be estimated. Meant for calibration and diagnostics. Layouts read `proximity`.
    public private(set) var faceDistance: FaceDistanceEstimate?
    /// Estimated brightness of the room in 0...1, smoothed. It comes from the camera's exposure,
    /// not from a light sensor, so it is an estimate of what the front camera sees. `nil` while
    /// the camera is not running, frames are not analyzed, or the camera has just started.
    public private(set) var roomBrightness: Double?
    /// Whether the room is dark enough for Night Mode. It changes only after the brightness has
    /// stayed past the threshold for several seconds. `nil` whenever `roomBrightness` is `nil`.
    public private(set) var isRoomDark: Bool?
    /// Members who have a stored face template.
    public private(set) var enrolledProfileIDs: Set<UUID> = []
    public private(set) var enrollment: FaceEnrollmentStatus?
    /// The latest failure to read or change stored face data.
    public private(set) var lastStoreError: FaceTemplateStoreError?

    public let activeEmbedderName: String
    /// True when no face model is bundled and the development fallback is in use.
    public let isUsingDevelopmentEmbedder: Bool
    /// Why the bundled model could not be loaded, when there is one and it failed.
    public let embedderLoadFailure: FaceEmbedderError?
    /// Feeds the camera preview.
    public let previewSource: FaceCameraPreviewSource

    /// The preference from Settings, for status displays.
    public var isRecognitionEnabled: Bool { preferences.recognitionEnabled }

    @ObservationIgnored private let session: HouseholdSession
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let store: any FaceTemplateStore
    @ObservationIgnored private let embedder: any FaceEmbedder
    @ObservationIgnored private let configuration: FaceRecognitionConfiguration
    @ObservationIgnored private let pipeline: FaceCameraPipeline
    @ObservationIgnored private let driver = HouseholdSessionDriver()

    private var preferences: FaceSettingsValues
    @ObservationIgnored private var engine: RecognitionEngine
    @ObservationIgnored private var governor: FrameRateGovernor
    @ObservationIgnored private var templates: [FaceTemplate] = []
    @ObservationIgnored private var knownProfileIDs: Set<UUID>
    @ObservationIgnored private var enrollmentSession: EnrollmentSession?
    @ObservationIgnored private var enrollmentLiveness: LivenessTracker
    @ObservationIgnored private var enrollmentGuidance = EnrollmentGuidance()
    @ObservationIgnored private var positionSmoother = FacePositionSmoother()
    @ObservationIgnored private var ambientLight: AmbientLightEstimator

    @ObservationIgnored private var isRequested = false
    @ObservationIgnored private var isMirrorActive = false
    @ObservationIgnored private var isAnalyzing = false
    @ObservationIgnored private var showsPreview = false
    @ObservationIgnored private var isForeground: Bool
    @ObservationIgnored private var isCameraRunning = false
    @ObservationIgnored private var lastRestartAt: TimeInterval?
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []

    /// - Parameters:
    ///   - settings: preferences from the system Settings app. They are read, never written.
    ///   - embedder: defaults to the bundled Core ML model, or the development fallback when the
    ///     bundle has none.
    public init(
        session: HouseholdSession,
        settings: HomePadSettings,
        store: any FaceTemplateStore = KeychainFaceTemplateStore(),
        embedder: ActiveFaceEmbedder = FaceEmbedderFactory.makeDefault(),
        configuration: FaceRecognitionConfiguration = FaceRecognitionConfiguration()
    ) {
        var configuration = configuration
        configuration.engine.matchPolicies.register(embedder.embedder.matchPolicy, forModelID: embedder.embedder.modelID)

        self.session = session
        self.settings = settings
        self.store = store
        self.embedder = embedder.embedder
        self.configuration = configuration
        self.activeEmbedderName = embedder.embedder.displayName
        self.isUsingDevelopmentEmbedder = embedder.embedder.isDevelopmentFallback
        self.embedderLoadFailure = embedder.loadFailure

        let preferences = Self.readPreferences(from: settings)
        self.preferences = preferences
        self.engine = RecognitionEngine(configuration: preferences.applied(to: configuration.engine))
        self.governor = FrameRateGovernor(policy: configuration.frameRates)
        self.enrollmentLiveness = LivenessTracker(policy: configuration.engine.liveness)
        self.ambientLight = AmbientLightEstimator(policy: configuration.ambientLight)
        self.knownProfileIDs = Set(session.profiles.map(\.id))
        self.isForeground = UIApplication.shared.applicationState != .background

        let (observations, continuation) = AsyncStream.makeStream(
            of: FaceFrameObservation.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        let processor = FaceFrameProcessor(
            analyzer: FaceAnalyzer(configuration: configuration.analyzer),
            embedder: embedder.embedder,
            minimumQualityForEmbedding: configuration.minimumQualityForEmbedding
        )
        let pipeline = FaceCameraPipeline(rates: configuration.frameRates) { frame in
            continuation.yield(processor.process(frame))
        }
        self.pipeline = pipeline
        self.previewSource = pipeline.previewSource

        reloadTemplates()
        frameTask = Task { [weak self] in
            for await observation in observations {
                self?.handle(observation)
            }
        }
        eventTask = Task { [weak self] in
            for await event in pipeline.events {
                self?.handle(event)
            }
        }
        observeLifecycle()
        trackPreferences()
        trackProfiles()
    }

    isolated deinit {
        frameTask?.cancel()
        eventTask?.cancel()
        let pipeline = pipeline
        Task { await pipeline.stop() }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Recognition

    /// Asks for recognition to run. The camera starts when the preference in Settings allows it
    /// and the app is in the foreground, and it follows both from then on. Shows the system
    /// camera prompt the first time.
    public func start() async {
        isRequested = true
        await reconcileCamera()
    }

    public func stop() async {
        isRequested = false
        await reconcileCamera()
    }

    // MARK: Mirror

    /// Tells the service that the mirror is on screen or gone. The device allows one capture
    /// session on the front camera, so the mirror shows this service's camera.
    ///
    /// While active, the camera runs at a smooth preview rate, with or without a face in view.
    /// It also runs when recognition is turned off in Settings or was never started. In that
    /// case frames are shown and not analyzed, and nobody is recognized. When inactive, the
    /// camera goes back to what recognition alone needs.
    public func setMirrorActive(_ active: Bool) async {
        isMirrorActive = active
        await reconcileCamera()
    }

    /// The live front camera view for the mirror. Call `setMirrorActive(true)` while it is on
    /// screen.
    public func makeMirrorPreview() -> some View {
        FaceMirrorView(service: self)
    }

    public func hasFace(for profileID: UUID) -> Bool {
        enrolledProfileIDs.contains(profileID)
    }

    public func householdName(for profileID: UUID) -> String? {
        session.profiles.first { $0.id == profileID }?.name
    }

    // MARK: Face data

    /// Deletes the member's face template, then removes the member from the household.
    public func removeProfile(id: UUID) throws {
        if enrollment?.profileID == id {
            endEnrollment()
        }
        try deleteFaceData(for: id)
        try session.removeProfile(id: id)
    }

    public func deleteFaceData(for profileID: UUID) throws(FaceTemplateStoreError) {
        defer { reloadTemplates() }
        try store.delete(profileID: profileID)
    }

    public func deleteAllFaceData() throws(FaceTemplateStoreError) {
        defer { reloadTemplates() }
        try store.deleteAll()
    }

    // MARK: Enrollment

    /// Starts collecting face samples for a member. Progress appears in `enrollment`. Starts the
    /// camera for the duration even when recognition is turned off in Settings.
    public func beginEnrollment(for profileID: UUID) async {
        enrollmentSession = nil
        enrollment = FaceEnrollmentStatus(profileID: profileID)
        // Nobody stays recognized while a face is being enrolled.
        resetRecognition()
        await reconcileCamera()
        guard enrollment?.profileID == profileID, enrollment?.phase == .starting else { return }
        guard isCameraRunning else {
            enrollment?.phase = .failed(cameraAuthorization == .authorized ? .cameraUnavailable : .cameraNotAuthorized)
            return
        }
        var policy = configuration.enrollment
        // Without depth no sample can be confirmed live, so the head-turn sequence itself is
        // the only liveness signal available.
        policy.allowsIndeterminateLiveness = policy.allowsIndeterminateLiveness || !hasDepthCamera
        enrollmentSession = EnrollmentSession(
            profileID: profileID,
            modelID: embedder.modelID,
            matchPolicy: embedder.matchPolicy,
            existingTemplates: templates,
            policy: policy
        )
        enrollmentLiveness.reset()
        enrollmentGuidance = EnrollmentGuidance()
        enrollment?.phase = .collecting
        updateFrameRate(facePresent: false, at: ProcessInfo.processInfo.systemUptime)
    }

    /// Ends an enrollment, finished or not, and returns the camera to what recognition needs.
    public func endEnrollment() {
        enrollmentSession = nil
        enrollment = nil
        Task { await reconcileCamera() }
    }

    // MARK: Frames

    private func handle(_ observation: FaceFrameObservation) {
        guard isCameraRunning, isAnalyzing else { return }
        let facePresent = observation.primary != nil
        if isFacePresent != facePresent {
            isFacePresent = facePresent
        }
        if positionSmoother.update(with: observation.primary?.viewerPosition) {
            facePosition = positionSmoother.position
        }
        if ambientLight.update(with: observation.light, at: observation.timestamp) {
            publishAmbientLight()
        }
        let distance = observation.primary?.distance.map {
            FaceDistanceEstimate(meters: ($0.meters * 20).rounded() / 20, source: $0.source)
        }
        if faceDistance != distance {
            faceDistance = distance
        }
        // Recognition pauses for as long as an enrollment screen is up, in any of its phases.
        if enrollmentSession != nil {
            handleEnrollment(observation)
        } else if enrollment == nil, isRequested, preferences.recognitionEnabled {
            let profileIDs = Set(session.profiles.map(\.id))
            publish(engine.process(observation, templates: templates.filter { profileIDs.contains($0.profileID) }))
        }
        updateFrameRate(facePresent: facePresent, at: observation.timestamp)
    }

    private func publish(_ update: RecognitionUpdate) {
        if lastDecision != update.outcome {
            lastDecision = update.outcome
        }
        if proximity != update.proximity {
            proximity = update.proximity
        }
        if update.didChange {
            driver.apply(update, to: session, at: Date())
        }
    }

    private func publishAmbientLight() {
        if roomBrightness != ambientLight.level {
            roomBrightness = ambientLight.level
        }
        if isRoomDark != ambientLight.isRoomDark {
            isRoomDark = ambientLight.isRoomDark
        }
    }

    /// The room is unknown whenever frames stop being analyzed.
    private func resetAmbientLight() {
        ambientLight.reset()
        publishAmbientLight()
    }

    private func resetRecognition() {
        engine = RecognitionEngine(configuration: preferences.applied(to: configuration.engine))
        if isFacePresent {
            isFacePresent = false
        }
        positionSmoother.reset()
        if facePosition != nil {
            facePosition = nil
        }
        if faceDistance != nil {
            faceDistance = nil
        }
        let changed = lastDecision != .nobody || session.isSomeonePresent
        publish(RecognitionUpdate(outcome: .nobody, proximity: .far, isFacePresent: false, liveness: nil, didChange: changed))
    }

    private func updateFrameRate(facePresent: Bool, at timestamp: TimeInterval) {
        guard let mode = governor.update(facePresent: facePresent, showsPreview: showsPreview, at: timestamp) else {
            return
        }
        Task { await pipeline.setMode(mode) }
    }

    private func handleEnrollment(_ observation: FaceFrameObservation) {
        guard var active = enrollmentSession else { return }
        var verdict = LivenessVerdict.indeterminate
        if let face = observation.primary {
            verdict = enrollmentLiveness.ingest(
                depth: face.depth,
                yaw: face.pose.yaw,
                eyeOpenness: face.eyeOpenness,
                at: observation.timestamp
            ).verdict
        } else {
            // Whoever comes back into view may be someone else.
            enrollmentLiveness.reset()
        }
        enrollmentGuidance.record(active.ingest(observation, liveness: verdict))
        enrollmentSession = active

        var status = enrollment
        status?.bucketProgress = Dictionary(uniqueKeysWithValues: active.policy.requiredBuckets.map { ($0, active.progress(in: $0)) })
        status?.progress = active.progress
        status?.nextBucket = active.nextBucket
        status?.issue = enrollmentGuidance.issue
        switch active.state {
        case .collecting:
            break
        case .blockedByDuplicate(let other):
            status?.phase = .failed(.duplicateFace(other))
            enrollmentSession = nil
        case .complete:
            status?.phase = saveTemplate(from: active)
            enrollmentSession = nil
        }
        if enrollment != status {
            enrollment = status
        }
        if enrollmentSession == nil {
            Task { await reconcileCamera() }
        }
    }

    private func saveTemplate(from finished: EnrollmentSession) -> FaceEnrollmentStatus.Phase {
        guard let template = finished.makeTemplate(createdAt: Date()) else {
            return .failed(.storageFailed(.encodingFailed))
        }
        do {
            try store.save(template)
        } catch {
            lastStoreError = error
            return .failed(.storageFailed(error))
        }
        reloadTemplates()
        return .finished
    }

    private func reloadTemplates() {
        do {
            templates = try store.loadAll()
            lastStoreError = nil
        } catch {
            templates = []
            lastStoreError = error
        }
        let ids = Set(templates.map(\.profileID))
        if enrolledProfileIDs != ids {
            enrolledProfileIDs = ids
        }
    }

    // MARK: Camera

    private func handle(_ event: FaceCameraEvent) {
        guard isCameraRunning else { return }
        switch event {
        case .interrupted(let reason):
            cameraState = .interrupted(reason)
            resetRecognition()
            resetAmbientLight()
        case .interruptionEnded:
            cameraState = .running
        case .runtimeError:
            isCameraRunning = false
            isAnalyzing = false
            cameraState = .stopped
            resetRecognition()
            resetAmbientLight()
            // One restart attempt per stretch of time, so a camera that keeps failing does not
            // spin.
            let now = ProcessInfo.processInfo.systemUptime
            if lastRestartAt.map({ now - $0 > 30 }) ?? true {
                lastRestartAt = now
                Task { await reconcileCamera() }
            }
        }
    }

    /// Brings the camera in line with what is wanted. Calls run one after another in order.
    private func reconcileCamera() async {
        let previous = reconcileTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.reconcileCameraOnce()
        }
        reconcileTask = task
        await task.value
    }

    private func reconcileCameraOnce() async {
        let plan = CameraDemand.plan(
            requested: isRequested,
            recognitionEnabled: preferences.recognitionEnabled,
            isEnrolling: enrollment?.isActive ?? false,
            isMirrorActive: isMirrorActive,
            isForeground: isForeground
        )
        if plan.runsCamera, !isCameraRunning {
            cameraAuthorization = await CameraAuthorization.request()
            guard cameraAuthorization == .authorized else {
                cameraState = .failed(.notAuthorized)
                return
            }
            do {
                // Set before the first frame, so a mirror-only start never analyzes one.
                await pipeline.setAnalysisEnabled(plan.analyzesFrames)
                hasDepthCamera = try await pipeline.start()
                governor.reset()
                isCameraRunning = true
                cameraState = .running
            } catch {
                cameraState = .failed(error)
                return
            }
        } else if !plan.runsCamera {
            if isCameraRunning {
                isCameraRunning = false
                await pipeline.stop()
            }
            cameraState = .stopped
        }

        let analyzes = isCameraRunning && plan.analyzesFrames
        if isCameraRunning {
            await pipeline.setAnalysisEnabled(analyzes)
        }
        if isAnalyzing, !analyzes {
            isAnalyzing = false
            resetRecognition()
            resetAmbientLight()
        }
        isAnalyzing = analyzes
        showsPreview = plan.showsPreview
        if isCameraRunning {
            updateFrameRate(facePresent: isFacePresent, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(false) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(true) }
            },
        ]
    }

    private func setForeground(_ foreground: Bool) {
        isForeground = foreground
        Task { await reconcileCamera() }
    }

    // MARK: Preferences and household changes

    private static func readPreferences(from settings: HomePadSettings) -> FaceSettingsValues {
        FaceSettingsValues(
            recognitionEnabled: settings[FaceSettings.recognitionEnabled],
            indeterminateLivenessPersonalizes: settings[FaceSettings.indeterminateLivenessPersonalizes],
            lockDelaySeconds: settings[FaceSettings.lockDelaySeconds],
            nearDistance: settings[FaceSettings.nearDistance],
            matchStrictness: settings[FaceSettings.matchStrictness]
        )
    }

    private func trackPreferences() {
        withObservationTracking {
            _ = Self.readPreferences(from: settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyPreferences()
                self?.trackPreferences()
            }
        }
    }

    private func applyPreferences() {
        let latest = Self.readPreferences(from: settings)
        guard latest != preferences else { return }
        preferences = latest
        resetRecognition()
        Task { await reconcileCamera() }
    }

    private func trackProfiles() {
        withObservationTracking {
            _ = session.profiles
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.profilesChanged()
                self?.trackProfiles()
            }
        }
    }

    /// Deletes the template of a member who was just removed from the household, whoever
    /// removed them. Only an observed removal triggers this, so a household list that failed to
    /// load at launch never wipes face data.
    private func profilesChanged() {
        let current = Set(session.profiles.map(\.id))
        let removed = knownProfileIDs.subtracting(current)
        knownProfileIDs = current
        guard !removed.isEmpty else { return }
        for profileID in removed {
            do {
                try store.delete(profileID: profileID)
            } catch {
                lastStoreError = error
            }
        }
        reloadTemplates()
    }
}
