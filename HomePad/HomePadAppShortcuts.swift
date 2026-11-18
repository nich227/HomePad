import AppIntents
import HomePadAssistant
import HomePadMessaging

/// Spoken phrases for the intents that make sense by voice: two for a companion and six that
/// act on the hub. The provider has to live
/// in the app target: declared in a package, its phrases do not reach the app's metadata.
struct HomePadAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowOnHomePadIntent(),
            phrases: [
                "Show \(\.$app) on \(.applicationName)",
                "Put \(\.$app) on \(.applicationName)",
                "Open \(\.$app) on \(.applicationName)",
            ],
            shortTitle: "Show on HomePad",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: BeamToHomePadIntent(),
            phrases: [
                "Beam a page to \(.applicationName)",
                "Send a page to \(.applicationName)",
            ],
            shortTitle: "Beam to HomePad",
            systemImageName: "dot.radiowaves.up.forward"
        )
        AppShortcut(
            intent: StartHubTimerIntent(),
            phrases: ["Start a timer on \(.applicationName)", "Set a \(.applicationName) timer"],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: CancelHubTimerIntent(),
            phrases: ["Cancel the timer on \(.applicationName)", "Stop the \(.applicationName) timer"],
            shortTitle: "Cancel Timer",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: ShowOnHubIntent(),
            phrases: ["Change what \(.applicationName) shows", "Switch the face on \(.applicationName)"],
            shortTitle: "Show Face or App",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: SetHubNightModeIntent(),
            phrases: [
                "Turn \(\.$state) Night Mode on \(.applicationName)",
                "Switch \(.applicationName) Night Mode \(\.$state)",
            ],
            shortTitle: "Night Mode",
            systemImageName: "moon.fill"
        )
        AppShortcut(
            intent: RunHubSceneIntent(),
            phrases: ["Run a scene on \(.applicationName)", "Run a \(.applicationName) scene"],
            shortTitle: "Run Scene",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: SetHubThermostatIntent(),
            phrases: ["Set the thermostat on \(.applicationName)", "Set the \(.applicationName) thermostat"],
            shortTitle: "Set Thermostat",
            systemImageName: "thermometer.medium"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
