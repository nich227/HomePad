import Foundation
import HomePadCore

/// Preferences for the Assistant. They are edited in the system Settings app; this package only
/// reads them.
public enum AssistantSettings {
    public static let pane = "Assistant"

    public static let enabled = SettingKey<Bool>("assistant.enabled", default: true)
    public static let speakAnswers = SettingKey<Bool>("assistant.speakAnswers", default: true)
    public static let listenOnOpen = SettingKey<Bool>("assistant.listenOnOpen", default: true)
    public static let usePersonalContext = SettingKey<Bool>("assistant.usePersonalContext", default: true)
    /// Seconds. Zero keeps the Assistant open until someone closes it.
    public static let autoDismissSeconds = SettingKey<Int>("assistant.autoDismissSeconds", default: 30)
    public static let formatRecipes = SettingKey<Bool>("assistant.formatRecipes", default: true)

    public static let descriptors: [SettingDescriptor] = [
        SettingDescriptor(
            enabled,
            title: "Assistant",
            pane: pane,
            footer: "The Assistant answers questions and controls this hub with the language model on this device. It opens only when you ask for it on the screen and never listens for a wake word. HomePad needs Apple Intelligence turned on whether or not the Assistant is on."
        ),
        SettingDescriptor(
            listenOnOpen,
            title: "Listen When Opened",
            pane: pane,
            footer: "When on, the Assistant starts listening as soon as it opens. When off, it waits for you to type or tap the microphone. Speech is recognized on this device and the microphone is used only while the Assistant shows that it is listening."
        ),
        SettingDescriptor(speakAnswers, title: "Speak Answers", pane: pane),
        SettingDescriptor(
            usePersonalContext,
            title: "Use Personal Context",
            pane: pane,
            footer: "When on, the Assistant may use your calendar events, your reminders, and what is playing on your iPhone in its answers, and only while your face has unlocked personal content on this hub. Guests never get personal context."
        ),
        SettingDescriptor(
            autoDismissSeconds,
            title: "Close Automatically",
            pane: pane,
            options: [
                .init(title: "Never", value: "0"),
                .init(title: "After 15 Seconds", value: "15"),
                .init(title: "After 30 Seconds", value: "30"),
                .init(title: "After 1 Minute", value: "60"),
                .init(title: "After 2 Minutes", value: "120"),
            ],
            footer: "How long the Assistant stays on screen after it answers and nobody touches it."
        ),
        SettingDescriptor(
            formatRecipes,
            title: "Tidy Up Recipes",
            pane: pane,
            footer: "When on, a recipe sent to this hub is laid out as short steps by the language model on this device. Nothing leaves this device, every amount and ingredient is checked against the page, and the original recipe stays one tap away."
        ),
    ]
}

/// A plain snapshot of the Assistant preferences. Pure logic takes this, never `HomePadSettings`.
public struct AssistantPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var speaksAnswers: Bool
    public var listensOnOpen: Bool
    public var usesPersonalContext: Bool
    /// Nil keeps the Assistant open until someone closes it.
    public var autoDismissAfter: TimeInterval?
    public var formatsRecipes: Bool

    public init(
        isEnabled: Bool = AssistantSettings.enabled.defaultValue,
        speaksAnswers: Bool = AssistantSettings.speakAnswers.defaultValue,
        listensOnOpen: Bool = AssistantSettings.listenOnOpen.defaultValue,
        usesPersonalContext: Bool = AssistantSettings.usePersonalContext.defaultValue,
        autoDismissSeconds: Int = AssistantSettings.autoDismissSeconds.defaultValue,
        formatsRecipes: Bool = AssistantSettings.formatRecipes.defaultValue
    ) {
        self.isEnabled = isEnabled
        self.speaksAnswers = speaksAnswers
        self.listensOnOpen = listensOnOpen
        self.usesPersonalContext = usesPersonalContext
        autoDismissAfter = autoDismissSeconds > 0 ? TimeInterval(autoDismissSeconds) : nil
        self.formatsRecipes = formatsRecipes
    }

    @MainActor
    public init(settings: HomePadSettings) {
        self.init(
            isEnabled: settings[AssistantSettings.enabled],
            speaksAnswers: settings[AssistantSettings.speakAnswers],
            listensOnOpen: settings[AssistantSettings.listenOnOpen],
            usesPersonalContext: settings[AssistantSettings.usePersonalContext],
            autoDismissSeconds: settings[AssistantSettings.autoDismissSeconds],
            formatsRecipes: settings[AssistantSettings.formatRecipes]
        )
    }
}
