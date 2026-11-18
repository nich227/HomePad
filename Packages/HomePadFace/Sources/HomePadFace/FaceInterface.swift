import HomePadCore
import HomePadFaceCore
import SwiftUI
import UIKit

extension Color {
    init(_ tint: RainbowTint) {
        let rgb = tint.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension RainbowTint {
    var localizedName: String {
        switch self {
        case .green: String(localized: "Green")
        case .yellow: String(localized: "Yellow")
        case .orange: String(localized: "Orange")
        case .red: String(localized: "Red")
        case .purple: String(localized: "Purple")
        case .blue: String(localized: "Blue")
        }
    }
}

extension HeadPoseBucket {
    var prompt: String {
        switch self {
        case .center: String(localized: "Look straight at the screen")
        case .left: String(localized: "Slowly turn your head to the left")
        case .right: String(localized: "Slowly turn your head to the right")
        case .up: String(localized: "Tilt your head up")
        case .down: String(localized: "Tilt your head down")
        }
    }
}

extension EnrollmentIssue {
    var message: String {
        switch self {
        case .noFace: String(localized: "Move into view of the camera")
        case .multipleFaces: String(localized: "Only one person at a time, please")
        case .tooFar: String(localized: "Move closer to the screen")
        case .poorQuality: String(localized: "Find better light and hold still")
        case .livenessNotConfirmed:
            String(localized: "The camera cannot confirm a real face. Face the screen from a little closer.")
        case .differentPerson:
            String(localized: "This looks like a different person. Start over to enroll someone else.")
        }
    }
}

extension CameraAuthorization {
    var statusText: String {
        switch self {
        case .authorized: String(localized: "Allowed")
        case .denied: String(localized: "Not allowed")
        case .restricted: String(localized: "Restricted on this device")
        case .notDetermined: String(localized: "Not asked yet")
        }
    }
}

@MainActor
enum SystemSettings {
    /// Opens this app's page in the system Settings app.
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
