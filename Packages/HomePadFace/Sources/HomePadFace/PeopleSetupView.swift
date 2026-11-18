import HomePadCore
import HomePadFaceCore
import SwiftUI

/// Setup for the household: add and remove members, enroll or re-enroll a face, and see what
/// face recognition is running on. Preferences are not changed here. They live in the system
/// Settings app.
public struct PeopleSetupView: View {
    private let session: HouseholdSession
    private let service: FaceRecognitionService

    @State private var newName = ""
    @State private var newTint: RainbowTint?
    @State private var enrolling: HouseholdProfile?
    @State private var pendingRemoval: HouseholdProfile?
    @State private var pendingFaceDeletion: HouseholdProfile?
    @State private var errorMessage: String?

    public init(session: HouseholdSession, service: FaceRecognitionService) {
        self.session = session
        self.service = service
    }

    public var body: some View {
        List {
            Section {
                if session.profiles.isEmpty {
                    Text("No one has been added yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(session.profiles) { profile in
                    memberRow(profile)
                }
            } header: {
                Text("Household")
            }

            Section {
                TextField(text: $newName) {
                    Text("Name")
                }
                .textContentType(.givenName)
                .submitLabel(.done)
                .onSubmit(addMember)
                tintPicker
                Button(action: addMember) {
                    Label {
                        Text("Add Person")
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Add a Person")
            }

            statusSection

            Section {
                Text("Face recognition runs entirely on this device. The camera image is analyzed and discarded right away. Only a numeric description of each enrolled face is kept, in this device's Keychain, and it is deleted when you delete face data or remove the person. Nothing about faces is sent anywhere or written to logs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("This is a convenience for a shared screen, not Face ID. Without a depth camera it can be fooled by a photo, which is why personal content stays locked unless the camera confirms a real face.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .fullScreenCover(item: $enrolling) { profile in
            FaceEnrollmentView(profile: profile, service: service) { _ in
                enrolling = nil
            }
        }
        .confirmationDialog(
            Text("Remove \(pendingRemoval?.name ?? "")?"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { profile in
            Button(role: .destructive) {
                remove(profile)
            } label: {
                Text("Remove Person and Face Data")
            }
        } message: { _ in
            Text("This deletes the person, their face data, and their place in the household on this device.")
        }
        .confirmationDialog(
            Text("Delete face data for \(pendingFaceDeletion?.name ?? "")?"),
            isPresented: Binding(get: { pendingFaceDeletion != nil }, set: { if !$0 { pendingFaceDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingFaceDeletion
        ) { profile in
            Button(role: .destructive) {
                deleteFace(of: profile)
            } label: {
                Text("Delete Face Data")
            }
        } message: { _ in
            Text("The hub will stop recognizing this person until a face is set up again.")
        }
        .alert(
            Text("Something Went Wrong"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(role: .cancel) {
                errorMessage = nil
            } label: {
                Text("OK")
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Members

    private func memberRow(_ profile: HouseholdProfile) -> some View {
        let hasFace = service.hasFace(for: profile.id)
        return HStack(spacing: 16) {
            Image(systemName: profile.symbolName)
                .font(.largeTitle)
                .foregroundStyle(Color(profile.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                Text(hasFace ? "Face set up" : "No face set up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Menu {
                Button {
                    enrolling = profile
                } label: {
                    Label {
                        Text(hasFace ? "Set Up Face Again" : "Set Up Face")
                    } icon: {
                        Image(systemName: "faceid")
                    }
                }
                if hasFace {
                    Button(role: .destructive) {
                        pendingFaceDeletion = profile
                    } label: {
                        Label {
                            Text("Delete Face Data")
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                }
                Button(role: .destructive) {
                    pendingRemoval = profile
                } label: {
                    Label {
                        Text("Remove Person")
                    } icon: {
                        Image(systemName: "person.badge.minus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Actions for \(profile.name)"))
        }
        .padding(.vertical, 4)
    }

    private var tintPicker: some View {
        HStack(spacing: 12) {
            Text("Color")
            Spacer()
            ForEach(RainbowTint.allCases, id: \.self) { tint in
                let isSelected = newTint == tint
                Button {
                    newTint = isSelected ? nil : tint
                } label: {
                    Circle()
                        .fill(Color(tint))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tint.localizedName))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func addMember() {
        do {
            try session.addProfile(name: newName, tint: newTint)
            newName = ""
            newTint = nil
        } catch HouseholdError.emptyName {
            errorMessage = String(localized: "Enter a name first.")
        } catch HouseholdError.profileLimitReached(let limit) {
            errorMessage = String(localized: "This household already has \(limit) people, which is the limit.")
        } catch {
            errorMessage = String(localized: "The person could not be saved.")
        }
    }

    private func remove(_ profile: HouseholdProfile) {
        do {
            try service.removeProfile(id: profile.id)
        } catch is FaceTemplateStoreError {
            errorMessage = String(localized: "The face data could not be deleted, so the person was not removed. Make sure the device is unlocked and try again.")
        } catch {
            errorMessage = String(localized: "The person could not be removed.")
        }
    }

    private func deleteFace(of profile: HouseholdProfile) {
        do {
            try service.deleteFaceData(for: profile.id)
        } catch {
            errorMessage = String(localized: "The face data could not be deleted. Make sure the device is unlocked and try again.")
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            LabeledContent {
                Text(service.isRecognitionEnabled ? "On" : "Off")
            } label: {
                Text("Face recognition")
            }
            LabeledContent {
                Text(service.activeEmbedderName)
            } label: {
                Text("Face model")
            }
            LabeledContent {
                Text(service.cameraAuthorization.statusText)
            } label: {
                Text("Camera access")
            }
            if service.cameraState == .running {
                LabeledContent {
                    Text(service.hasDepthCamera ? "Available" : "Not available")
                } label: {
                    Text("Depth check")
                }
            }
            if service.isUsingDevelopmentEmbedder {
                Label {
                    Text("No face model is installed. The stand-in that is running cannot tell people apart reliably and is for development only.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }
            if service.lastStoreError != nil {
                Label {
                    Text("Stored face data could not be read. Make sure the device is unlocked.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }
            Button {
                SystemSettings.open()
            } label: {
                Label {
                    Text("Open HomePad Settings")
                } icon: {
                    Image(systemName: "gear")
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Turn recognition on or off, and change how it behaves, in the Settings app under HomePad.")
        }
    }
}
