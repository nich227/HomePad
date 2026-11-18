import AppIntents
import HomePadMessaging

/// Spoken phrases for the two intents that make sense by voice. Relaying a message is left out
/// on purpose: it is driven by an automation, not by a person asking. The provider has to live
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
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
