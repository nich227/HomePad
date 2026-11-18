import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadFaceCore
import SwiftUI

public enum FaceEnrollmentResult: Equatable, Sendable {
    case enrolled
    case canceled
}

/// Guides one household member through face enrollment: an explanation and consent first, then
/// a live preview with prompts to look straight, left, right, up, and down.
public struct FaceEnrollmentView: View {
    private let profile: HouseholdProfile
    private let service: FaceRecognitionService
    private let onFinish: (FaceEnrollmentResult) -> Void

    @State private var hasConsented = false

    public init(
        profile: HouseholdProfile,
        service: FaceRecognitionService,
        onFinish: @escaping (FaceEnrollmentResult) -> Void
    ) {
        self.profile = profile
        self.service = service
        self.onFinish = onFinish
    }

    public var body: some View {
        Group {
            if !hasConsented {
                consent
            } else if let status = service.enrollment, status.profileID == profile.id {
                switch status.phase {
                case .starting:
                    ProgressView {
                        Text("Starting the camera")
                    }
                    .controlSize(.large)
                case .collecting:
                    capture(status)
                case .finished:
                    finished
                case .failed(let failure):
                    failed(failure)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(alignment: .topLeading) {
            if service.enrollment?.phase != .finished {
                Button("Cancel", systemImage: "xmark") {
                    finish(.canceled)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(16)
                .accessibilityLabel(Text("Cancel face setup"))
            }
        }
        .onDisappear {
            // Covers dismissal by a system gesture, which bypasses the buttons.
            if service.enrollment?.profileID == profile.id {
                service.endEnrollment()
            }
        }
    }

    private func finish(_ result: FaceEnrollmentResult) {
        service.endEnrollment()
        onFinish(result)
    }

    // MARK: Consent

    private var consent: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(profile.tint))
                    .accessibilityHidden(true)
                Text("Set Up Face Recognition for \(profile.name)")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 16) {
                    ConsentPoint(
                        symbol: "camera",
                        text: Text("The front camera looks at your face while you turn your head. No photo or video is saved.")
                    )
                    ConsentPoint(
                        symbol: "lock.shield",
                        text: Text("A numeric description of your face is stored in this device's Keychain. It never leaves this device and is not synced or backed up to another device.")
                    )
                    ConsentPoint(
                        symbol: "person.2",
                        text: Text("The hub uses it to recognize you and show your content when you are in front of the screen.")
                    )
                    ConsentPoint(
                        symbol: "exclamationmark.triangle",
                        text: Text("This is a convenience, not Face ID. It is less secure than Face ID and could be fooled, so do not rely on it to protect sensitive information.")
                    )
                    ConsentPoint(
                        symbol: "trash",
                        text: Text("You can delete your face data at any time in People. Removing a person deletes it too.")
                    )
                }
                .frame(maxWidth: 560, alignment: .leading)
                VStack(spacing: 12) {
                    Button {
                        hasConsented = true
                        Task { await service.beginEnrollment(for: profile.id) }
                    } label: {
                        Text("Agree and Continue")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(profile.tint))
                    Button {
                        finish(.canceled)
                    } label: {
                        Text("Not Now")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Capture

    private func capture(_ status: FaceEnrollmentStatus) -> some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let diameter = min(proxy.size.width * (isWide ? 0.45 : 0.8), proxy.size.height * (isWide ? 0.8 : 0.5))
            let layout = isWide ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(spacing: 28))
            layout {
                ZStack {
                    HomePadAnimationView(.faceScan, loop: true, isPlaying: true, tint: Color(profile.tint))
                        .frame(width: diameter * 1.2, height: diameter * 1.2)
                    FaceCameraPreview(source: service.previewSource, isRunning: service.cameraState == .running)
                        .frame(width: diameter * 0.82, height: diameter * 0.82)
                        .clipShape(.circle)
                        .accessibilityHidden(true)
                    EnrollmentProgressRing(status: status, tint: Color(profile.tint))
                        .frame(width: diameter, height: diameter)
                }
                .frame(width: diameter * 1.2, height: diameter * 1.2)
                CapturePrompt(status: status)
                    .frame(maxWidth: isWide ? proxy.size.width * 0.4 : .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Results

    private var finished: some View {
        VStack(spacing: 24) {
            HomePadAnimationView(authored: .success, tint: Color(profile.tint))
                .frame(width: 220, height: 220)
            Text("Face Recognition Is Ready")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("The hub will recognize \(profile.name) from now on.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                finish(.enrolled)
            } label: {
                Text("Done")
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(profile.tint))
            .controlSize(.large)
        }
    }

    private func failed(_ failure: FaceEnrollmentFailure) -> some View {
        VStack(spacing: 24) {
            Image(systemName: failure == .cameraNotAuthorized ? "video.slash" : "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(failureTitle(failure))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(failureMessage(failure))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            VStack(spacing: 12) {
                if failure == .cameraNotAuthorized {
                    Button {
                        SystemSettings.open()
                    } label: {
                        Text("Open Settings")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.glassProminent)
                } else if case .duplicateFace = failure {
                    EmptyView()
                } else {
                    Button {
                        Task { await service.beginEnrollment(for: profile.id) }
                    } label: {
                        Text("Try Again")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button {
                    finish(.canceled)
                } label: {
                    Text("Close")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }

    private func failureTitle(_ failure: FaceEnrollmentFailure) -> String {
        switch failure {
        case .cameraNotAuthorized: String(localized: "Camera Access Is Off")
        case .cameraUnavailable: String(localized: "The Camera Is Not Available")
        case .duplicateFace: String(localized: "This Face Is Already Enrolled")
        case .storageFailed: String(localized: "The Face Data Could Not Be Saved")
        }
    }

    private func failureMessage(_ failure: FaceEnrollmentFailure) -> String {
        switch failure {
        case .cameraNotAuthorized:
            return String(localized: "Face recognition needs the camera. Allow camera access for HomePad in Settings, then come back.")
        case .cameraUnavailable:
            return String(localized: "Another app may be using the camera, or this device has no front camera.")
        case .duplicateFace(let other):
            let name = service.householdName(for: other) ?? String(localized: "another person")
            return String(localized: "This face already belongs to \(name). Each person can be enrolled once.")
        case .storageFailed:
            return String(localized: "Make sure the device is unlocked and try again.")
        }
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            text
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CapturePrompt: View {
    let status: FaceEnrollmentStatus

    private var prompt: String {
        status.nextBucket?.prompt ?? String(localized: "Hold still")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(prompt)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(status.issue?.message ?? " ")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(status.issue == nil)
            ProgressView(value: status.progress)
                .frame(maxWidth: 280)
                .accessibilityLabel(Text("Face setup progress"))
        }
        .animation(.default, value: prompt)
        .onChange(of: prompt, initial: true) { _, latest in
            AccessibilityNotification.Announcement(latest).post()
        }
        .onChange(of: status.issue) { _, issue in
            if let issue {
                AccessibilityNotification.Announcement(issue.message).post()
            }
        }
    }
}

/// Four arcs for left, up, right, and down around the preview, and an inner ring for the
/// straight-ahead pose. Each fills as samples of that pose are captured.
private struct EnrollmentProgressRing: View {
    let status: FaceEnrollmentStatus
    let tint: Color

    /// Where each arc sits, as the angle of its middle in degrees clockwise from the right. The
    /// preview is mirrored, so a turn to the person's left moves their face toward the left of
    /// the screen, and that is where the arc for it is.
    private static let arcs: [(bucket: HeadPoseBucket, middle: Double)] = [
        (.right, 0), (.down, 90), (.left, 180), (.up, 270),
    ]
    private static let arcFraction = 82.0 / 360.0

    var body: some View {
        GeometryReader { proxy in
            let lineWidth = max(6, proxy.size.width * 0.03)
            ZStack {
                ForEach(Self.arcs, id: \.bucket) { arc in
                    segment(progress: status.bucketProgress[arc.bucket] ?? 0, lineWidth: lineWidth)
                        .rotationEffect(.degrees(arc.middle - Self.arcFraction * 180))
                }
                Circle()
                    .stroke(.tertiary, lineWidth: lineWidth / 2)
                    .padding(lineWidth * 1.6)
                Circle()
                    .trim(from: 0, to: status.bucketProgress[.center] ?? 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth * 1.6)
            }
            .padding(lineWidth / 2)
            .animation(.snappy, value: status.bucketProgress)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Face setup progress"))
        .accessibilityValue(Text(status.progress, format: .percent.precision(.fractionLength(0))))
    }

    /// An arc that starts at the right of the circle and fills outward from its own middle.
    private func segment(progress: Double, lineWidth: CGFloat) -> some View {
        let span = Self.arcFraction
        return ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(.tertiary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: span * (1 - progress) / 2, to: span * (1 + progress) / 2)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(progress > 0 ? 1 : 0)
        }
    }
}
