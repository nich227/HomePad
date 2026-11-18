import AppIntents
import HomePadAnimations
import HomePadAssistant
import HomePadAnimationsCore
import HomePadCore
import HomePadMessaging
import HomePadUI
import SwiftUI

@main
struct HomePadApp: App {
    // Built when the app struct is created, so App Intents that launch the app without a scene
    // still find the companion's services.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
        }
    }
}

/// Tells the system which packages contribute App Intents to this app.
struct HomePadAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HomePadMessagingIntents.self, HomePadAssistantIntents.self]
    }
}

struct AppRootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    private var role: DeviceRole {
        HomePadRootView.role(settings: model.settings)
    }

    var body: some View {
        Group {
            if model.gate.mayRun {
                scene
            } else {
                AppleIntelligenceRequiredView(gate: model.gate)
            }
        }
        .task(id: Launch(role: role, mayRun: model.gate.mayRun)) {
            await model.configure(for: role, mayRun: model.gate.mayRun)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(to: phase)
        }
    }

    private struct Launch: Hashable {
        let role: DeviceRole
        let mayRun: Bool
    }

    @ViewBuilder private var scene: some View {
        switch model.phase {
        case .starting:
            StartingView()
        case .hub(let hub):
            HubSceneView(model: model, hub: hub)
        case .companion(let companion):
            CompanionSceneView(model: model, companion: companion)
        case .failed(let message):
            ContentUnavailableView {
                Label("HomePad Could Not Start", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            }
        }
    }
}

private struct StartingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            HomePadAnimationView(authored: .hello)
                .frame(width: 280, height: 280)
        }
        .accessibilityLabel("HomePad is starting")
    }
}
