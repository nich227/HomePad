import Foundation
import HomePadAssistantCore
import HomePadCore

extension AssistantEngine {
    /// The engine the app uses: the language model on this device, speech recognized on this
    /// device, and the system's voice. The audience is read from `session` at every step, so
    /// the rules follow whoever is in front of the hub at that moment.
    public convenience init(
        actions: any AssistantActions,
        hub: any AssistantHubContext,
        session: HouseholdSession,
        settings: HomePadSettings,
        hooks: AssistantTestHooks = .current
    ) {
        let responder: any AssistantResponder
        let speechInput: any AssistantSpeechInput
        let speechOutput: any AssistantSpeechOutput
        if hooks.usesScriptedAssistant {
            let silent = SilentSpeech()
            responder = ScriptedAssistantResponder()
            speechInput = silent
            speechOutput = silent
        } else {
            responder = FoundationModelResponder()
            speechInput = OnDeviceSpeechInput()
            speechOutput = SpokenAnswerOutput()
        }
        self.init(
            actions: actions,
            hub: hub,
            audience: { AssistantAudience(session: session) },
            preferences: { AssistantPreferences(settings: settings) },
            responder: responder,
            speechInput: speechInput,
            speechOutput: speechOutput,
            reportText: { $0.dialogText }
        )
    }

    /// An engine that answers from a script and never uses the microphone, the speaker, or
    /// the model. For previews and for UI tests.
    public static func scripted(
        actions: any AssistantActions,
        hub: any AssistantHubContext,
        audience: AssistantAudience = .guest,
        preferences: AssistantPreferences = AssistantPreferences(listensOnOpen: false, autoDismissSeconds: 0),
        lines: [ScriptedAssistantResponder.Line] = ScriptedAssistantResponder.sampleLines
    ) -> AssistantEngine {
        let silent = SilentSpeech()
        return AssistantEngine(
            actions: actions,
            hub: hub,
            audience: { audience },
            preferences: { preferences },
            responder: ScriptedAssistantResponder(lines: lines),
            speechInput: silent,
            speechOutput: silent,
            reportText: { $0.dialogText }
        )
    }
}
