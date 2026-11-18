import HomePadAnimations
import HomePadAnimationsCore
import HomePadCore
import HomePadFaceCore
import SwiftUI

/// A small capsule that says who the hub sees: a recognized member, a member whose personal
/// content is locked, a guest, nobody, or that the camera is off.
public struct RecognitionIndicatorView: View {
    private let service: FaceRecognitionService
    private let session: HouseholdSession

    public init(service: FaceRecognitionService, session: HouseholdSession) {
        self.service = service
        self.session = session
    }

    private enum Presentation: Equatable {
        case cameraOff
        case nobody
        case guest
        case locked(HouseholdProfile)
        case recognized(HouseholdProfile)
    }

    private var presentation: Presentation {
        guard service.cameraState == .running else { return .cameraOff }
        switch service.lastDecision {
        case .nobody:
            return .nobody
        case .unknownPerson:
            return .guest
        case .personalized(let id):
            return session.profiles.first { $0.id == id }.map(Presentation.locked) ?? .guest
        case .unlocked(let id):
            return session.profiles.first { $0.id == id }.map(Presentation.recognized) ?? .guest
        }
    }

    public var body: some View {
        let presentation = presentation
        // Larger when the person is across the room.
        let isFar = session.proximity == .far
        HStack(spacing: isFar ? 12 : 8) {
            icon(for: presentation)
                .frame(width: isFar ? 44 : 30, height: isFar ? 44 : 30)
            if let title = title(for: presentation) {
                Text(title)
                    .font(isFar ? .title2.weight(.semibold) : .headline)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isFar ? 18 : 12)
        .padding(.vertical, isFar ? 10 : 6)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy, value: presentation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(for: presentation)))
    }

    @ViewBuilder
    private func icon(for presentation: Presentation) -> some View {
        switch presentation {
        case .cameraOff:
            Image(systemName: "video.slash")
                .foregroundStyle(.secondary)
        case .nobody:
            Image(systemName: "person.crop.circle.dashed")
                .foregroundStyle(.secondary)
        case .guest:
            HomePadAnimationView(authored: .guest)
        case .locked(let profile):
            HomePadAnimationView(authored: .locked, tint: Color(profile.tint))
        case .recognized(let profile):
            ZStack {
                HomePadAnimationView(authored: .presencePulse, tint: Color(profile.tint))
                Image(systemName: profile.symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(Color(profile.tint))
            }
        }
    }

    private func title(for presentation: Presentation) -> String? {
        switch presentation {
        case .cameraOff, .nobody: nil
        case .guest: String(localized: "Guest")
        case .locked(let profile), .recognized(let profile): profile.name
        }
    }

    private func accessibilityText(for presentation: Presentation) -> String {
        switch presentation {
        case .cameraOff: String(localized: "Face recognition camera is off")
        case .nobody: String(localized: "No one is in front of the hub")
        case .guest: String(localized: "Guest. No household member recognized.")
        case .locked(let profile): String(localized: "\(profile.name). Personal content is locked.")
        case .recognized(let profile): String(localized: "\(profile.name) recognized")
        }
    }
}
