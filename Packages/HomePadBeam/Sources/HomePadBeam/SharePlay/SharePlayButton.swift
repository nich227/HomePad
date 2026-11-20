import GroupActivities
import HomePadBeamCore
import SwiftUI
import UIKit
import _GroupActivities_UIKit

/// Starts browsing a page together. In a call it starts right away; otherwise it shows the
/// system sheet for choosing people.
public struct SharePlayButton: View {
    private let coordinator: SharePlayCoordinator
    private let url: URL
    private let title: String?

    @State private var isInviting = false
    @State private var didFail = false

    public init(coordinator: SharePlayCoordinator, url: URL, title: String?) {
        self.coordinator = coordinator
        self.url = url
        self.title = title
    }

    private var validated: ValidatedURL? {
        try? BeamURLPolicy().validate(url).get()
    }

    public var body: some View {
        if coordinator.isEnabled, let validated {
            if coordinator.isActive {
                Button("Stop Browsing Together", systemImage: "shareplay.slash") { coordinator.leave() }
            } else if !coordinator.allowsInvitations {
                // A hub has no sheet for picking people and nothing for the system to offer, so
                // the button is there only while a call can take the page.
                if coordinator.isEligibleForGroupSession {
                    Button("Browse Together", systemImage: "shareplay") {
                        Task {
                            if await coordinator.startSharing(validated, title: title) == .failed {
                                didFail = true
                            }
                        }
                    }
                    .alert(Text("SharePlay could not start"), isPresented: $didFail) {
                        Button("OK", role: .cancel) {}
                    }
                }
            } else {
                Button("Browse Together", systemImage: "shareplay") {
                    Task {
                        switch await coordinator.startSharing(validated, title: title) {
                        case .needsInvitation: isInviting = true
                        case .failed: didFail = true
                        case .activated, .cancelled, .disabled: break
                        }
                    }
                }
                .background {
                    // Not shown. Its presence is what lets the system offer this page when two
                    // iPhones are held together.
                    ShareLink(
                        item: BeamTogetherActivity(url: validated, title: title),
                        preview: SharePreview(title ?? validated.url.host() ?? "")
                    )
                    .hidden()
                    .accessibilityHidden(true)
                }
                .sheet(isPresented: $isInviting) {
                    SharingControllerView(activity: BeamTogetherActivity(url: validated, title: title))
                }
                .alert(Text("SharePlay could not start"), isPresented: $didFail) {
                    Button("OK", role: .cancel) {}
                }
            }
        }
    }
}

private struct SharingControllerView: UIViewControllerRepresentable {
    let activity: BeamTogetherActivity

    func makeUIViewController(context: Context) -> UIViewController {
        (try? GroupActivitySharingController(activity)) ?? UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
