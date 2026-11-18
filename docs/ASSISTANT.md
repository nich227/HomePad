# Assistant and the Apple Intelligence requirement

HomePad needs Apple Intelligence to be on, and it has its own Assistant overlay that answers
questions and controls the hub with the language model on the device.

Code: `Packages/HomePadAssistant` (targets `HomePadAssistantCore` and `HomePadAssistant`).

## What it is and what it is not

The Assistant is not Siri. iOS gives a third-party app no way to be Siri, so HomePad does these
things instead:

| HomeView | HomePad |
|---|---|
| Wakes on "Siri" or "Hey Siri" | No wake word. The Assistant opens from the hub's screen. The microphone is on only while the card shows it is listening |
| Siri's own overlay | `AssistantOverlayView`: an edge light around the screen and a glass card at the bottom |
| Siri's name and icon | The feature is called "Assistant" everywhere. The word Siri appears only in the gate screen, to name the Settings pane |
| Siri's knowledge of the person | Only what the hub hands over, and only what the person in front of it may see |
| Siri acting in the app | The real Siri can run the same actions through App Intents (see below) |

What the Assistant uses, all on the device:

| Part | Framework | Type |
|---|---|---|
| Answers, tools, guided generation | FoundationModels | `FoundationModelResponder`, `AssistantTools`, `GeneratedReply` |
| Speech in | Speech, `SFSpeechRecognizer` with `requiresOnDeviceRecognition` | `OnDeviceSpeechInput` |
| Speech out | AVFoundation, `AVSpeechSynthesizer` | `SpokenAnswerOutput` |

Nothing in the package opens a network connection. Nothing in it logs a transcript, a prompt, or
an answer.

## The gate

`AppleIntelligenceGate` reads `SystemLanguageModel.default.availability` when it is created, each
time `refresh()` is called (the app calls it when the scene becomes active), when the system model
announces a change, and every 5 seconds while the model is preparing. That value is the only
public sign that Apple Intelligence is on. The iOS 27.2 SDK has no public call that reports the
state of Siri itself.

| System value | `AssistantAvailability` | What the app does |
|---|---|---|
| `available` | `available` | Runs |
| `unavailable(.appleIntelligenceNotEnabled)` | `needsAppleIntelligence` | Blocked: "Turn On Apple Intelligence", with a button to Settings |
| `unavailable(.deviceNotEligible)` | `deviceNotEligible` | Blocked: "This Device Is Not Supported", no button |
| `unavailable(.modelNotReady)` | `preparing` | See the grace period |
| any reason added later | `unknown` | Blocked: "Apple Intelligence Is Not Available", with a button to Settings |

The grace period (`AssistantGateState.preparingGracePeriod`, 10 minutes) covers a model that is
on but still downloading or loading:

- At launch, or after the app was blocked, the hub does not run. A "Getting Ready" screen waits
  and gives way by itself when the model is available.
- A hub that was already running keeps running, so a wall display does not go blank while the
  system swaps the model's files. The Assistant itself reports that it is unavailable until the
  model is back.
- After 10 minutes of preparing, both cases are blocked with "Still Getting Ready", which says
  to keep the device on power and Wi-Fi and offers Settings.

`AppleIntelligenceRequiredView(gate:)` is the screen. Its button opens HomePad's own page in
Settings, the only place in Settings an app may open. The text names the pane to go to:
Apple Intelligence & Siri.

UI tests bypass the gate with `HOMEPAD_UITEST_SKIP_AI_GATE=1` in the launch environment. It is
read in one place, `AssistantTestHooks.current`, and only in debug builds.
`HOMEPAD_UITEST_SCRIPTED_ASSISTANT=1` makes `AssistantEngine` answer from a fixed script with no
model, microphone, or speaker.

## Privacy rules

All of these are decided in `HomePadAssistantCore` and unit tested.

1. **Filtering comes before the prompt.** `AssistantPolicy.allowedContext` is the only way to
   make an `AssistantAllowedContext`, and `AssistantPrompt` takes nothing else. An item is
   personal when its kind is a calendar event, message, or reminder, or when it has an owner. A
   personal item passes only while `HouseholdSession.isPersonalContentUnlocked` is true and the
   item's owner is the active member. A guest, a profile picked by hand, and a recognized member
   waiting for their paired iPhone get shared context only. The model is never given something
   it may not reveal.
2. **Snippets come from allowed context only.** The model names the context lines it used by
   tag. Tags that do not match an allowed line are dropped.
3. **Who may ask for what** (`AssistantCapability.access`, enforced by `AssistantRouter`):

   | Needs | Capabilities |
   |---|---|
   | Anyone | timers, show a face or app, Night Mode, weather, accessories, thermostat, read the screen |
   | A household member, however selected | open a web page, send a household note |
   | A member the camera recognized | run a scene |

   The same check runs for the model's tools and for App Intents. The model is not offered a
   tool the audience may not use, and the router refuses it anyway.
4. **One session per conversation.** The model's session is dropped when the overlay closes.
   It is also dropped when the audience differs from the one of the previous request.
5. **A session that holds personal context ends when the audience changes.** While the overlay
   is open, the engine compares the audience twice a second. If the session was given personal
   context and someone else, or nobody, is now in front of the hub, the overlay closes and the
   session is dropped.
6. **Text from the hub and from people is data.** Every piece is folded onto one line and cut
   to a limit before it enters a prompt, so it cannot pass for a new section. The instructions
   tell the model not to follow instructions found in context or tool results.
7. **Limits.** At most 8 context items, 6 actions per request, a 400 character request, a 480
   character answer, and 280 spoken characters in at most 3 sentences.
8. **The microphone** runs from the moment listening starts until the request is sent, canceled,
   or timed out (8 seconds without speech). The overlay closes when the scene stops being
   active, which releases it. There is no background mode.
9. **Web pages** must be `http` or `https` with a host and without a user name or password.

The setting Use Personal Context turns rule 1 off for everyone: no personal item passes.

## Actions

The app implements `AssistantActions` over its own models. Each method returns
`Result<Value, AssistantActionError>`.

| Request | `AssistantActions` method | Checked before the call |
|---|---|---|
| `startTimer(name:seconds:)` | `startTimer(name:duration:)` | 1 second to 24 hours |
| `pauseTimer(name:)`, `cancelTimer(name:)`, `listTimers` | `pauseTimer`, `cancelTimer`, `timers` | |
| `show(name:)` | `show(named:)` | name not empty |
| `setNightMode(isOn:)` | `setNightMode(_:)` | |
| `runScene(name:)` | `runScene(named:)` | recognized member, name not empty |
| `setThermostat(degrees:scale:)` | `setThermostat(targetCelsius:)` | 5 to 35 degrees Celsius, rounded to half a degree |
| `setAccessory(name:isOn:)` | `setAccessory(named:isOn:)` | name not empty |
| `weather` | `weatherSummary()` | |
| `openWebPage(address:)` | `openWebPage(_:)` | household member, valid web address |
| `sendNote(text:)` | `sendHouseholdNote(_:)` | household member, note not empty |
| `readScreen` | `screenSummary()` | |

`AssistantActionError`: `needsHouseholdMember`, `needsRecognizedMember`,
`personalContentLocked`, `notFound(name)`, `unavailable`, `invalid(reason)`, `limitReached`.
The hub's implementation returns `personalContentLocked` when asked to show an app that the
person in front of it may not open, and must leave out of `screenSummary()` anything hidden from
that person.

The app also implements `AssistantHubContext`: `hubState` (hub name, screen title, Night Mode,
temperature unit) and `contextItems()` (timers, weather, home, now playing, and personal items
with their owner's id).

## Conversation

`AssistantConversation` is the state machine: idle, listening, thinking, answering, follow-ups,
failed. `AssistantEngine` runs it and carries out its effects.

- Listening ends when the recognizer finishes, after 1.6 seconds of silence following speech, or
  when the microphone button is tapped. With nothing heard for 8 seconds it fails with "no speech".
- A request with no progress for 30 seconds times out.
- Tapping the microphone or sending a new request stops speech and cancels the answer in progress.
- An answer whose session ran out of room is retried once in a fresh session, unless an action
  already ran.
- The overlay closes by itself after the Close Automatically time once speaking has ended and
  nobody touches it.
- Follow-up chips: at most three. Chips derived from what the hub just did come first (pause or
  cancel the timer that was started, the opposite Night Mode or accessory state), then the
  model's suggestions that are 2 to 36 characters, new, and not the request itself.

## Overlay

`AssistantOverlayView(engine:isNight:onDismiss:)` is see-through except for:

- An edge light on `ConcentricRectangle`, so it follows the display's corners, drawn past the
  safe area. With Reduce Motion it is one still frame.
- A card at the bottom, as wide as the display minus 16 points a side up to 720 points. It holds
  the request, the streaming answer, context snippets, follow-up chips, a text field, and a
  microphone button. It is Liquid Glass, or a solid fill with Reduce Transparency.

It closes on a tap outside the card, a swipe down on the card, the Close button, the
accessibility escape gesture, and when the scene stops being active. With `isNight` true it
draws in `AssistantPalette.night`: pure black and the Night Mode red only, with no glass. Text
uses ordinary text styles, so the hub's text scale and Dynamic Type apply.

## Settings

Pane "Assistant". `AssistantSettings.descriptors` must be appended in
`SettingsCatalog.descriptors`.

| Key | Title | Default |
|---|---|---|
| `assistant.enabled` | Assistant | on |
| `assistant.listenOnOpen` | Listen When Opened | on |
| `assistant.speakAnswers` | Speak Answers | on |
| `assistant.usePersonalContext` | Use Personal Context | on |
| `assistant.autoDismissSeconds` | Close Automatically | 30 (choices 0 for never, 15, 30, 60, 120) |

Turning the Assistant off hides the overlay. It does not lift the gate.

## App Intents

`HomePadAssistantIntents` is the `AppIntentsPackage`. The intents call
`AssistantIntentHandlers.shared.perform`, which the app sets with
`AssistantIntentHandlers.shared.register(engine:)`. The rules above apply: Siri cannot run a
scene on a hub that recognizes nobody in front of it.

| Intent | Parameters |
|---|---|
| `StartHubTimerIntent` | duration, name (optional) |
| `CancelHubTimerIntent` | name (optional) |
| `ShowOnHubIntent` | name of a face or app. Opens the app in the foreground |
| `SetHubNightModeIntent` | on or off (`HubSwitchState`) |
| `RunHubSceneIntent` | scene name |
| `SetHubThermostatIntent` | temperature |

Phrases for `HomePad/HomePadAppShortcuts.swift` (the provider must stay in the app target):

```swift
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
    phrases: ["Turn \(\.$state) Night Mode on \(.applicationName)", "Switch \(.applicationName) Night Mode \(\.$state)"],
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
```

The phrases for showing a face avoid "Show ... on HomePad" and "Open ... on HomePad", which
`ShowOnHomePadIntent` already uses for a projected app.

## Info.plist keys and entitlements

| Key | Suggested text |
|---|---|
| `NSMicrophoneUsageDescription` | HomePad listens through the microphone only while the Assistant shows that it is listening. Audio is processed on this device and is never stored or sent anywhere. |
| `NSSpeechRecognitionUsageDescription` | HomePad turns what you say to the Assistant into text on this device. Nothing you say is sent to Apple or anywhere else. |

No entitlement, capability, or background mode is needed. The on-device model needs none. App
Intents do not need the Siri entitlement. Do not add the `audio` background mode: the microphone
must never run in the background.

## Private Cloud Compute

The iOS 27 SDK has `PrivateCloudComputeLanguageModel`, which a session accepts in place of the
on-device model. Its documentation says an app must meet eligibility requirements and request a
managed entitlement before it can use it. HomePad does not have that entitlement, and the type
sends requests to Apple's servers, so the Assistant uses `SystemLanguageModel.default` only.

## Wiring into the app

| Where | What |
|---|---|
| `project.yml` | Add the package and both products to the app target, add the two usage descriptions, then `xcodegen generate` |
| `SettingsCatalog.descriptors` | Append `AssistantSettings.descriptors`, then `Scripts/generate-settings.sh` |
| `HomePadApp.swift` | Add `HomePadAssistantIntents.self` to `includedPackages`. Show `AppleIntelligenceRequiredView(gate:)` instead of the scene while `gate.mayRun` is false |
| `AppModel.swift` | Create `AppleIntelligenceGate()` and call `refresh()` when the scene becomes active. Create `AssistantEngine(actions:hub:session:settings:)` and call `AssistantIntentHandlers.shared.register(engine:)` before any scene exists |
| `HubSceneView.swift` | Present `AssistantOverlayView` above the hub while `engine.isEnabled`, from a control of the hub's own |
| `HomePadAppShortcuts.swift` | Add the phrases above |
| `HomePadUITests` | Set `HOMEPAD_UITEST_SKIP_AI_GATE=1`, and `HOMEPAD_UITEST_SCRIPTED_ASSISTANT=1` to exercise the overlay |

## Files

| File | Holds |
|---|---|
| `Core/AssistantAvailability.swift` | `SystemModelStatus`, `AssistantAvailability`, `AssistantGateState`, `AssistantGateDecision`, `AssistantTestHooks` |
| `Core/AssistantAudience.swift` | `AssistantAudience`, `AssistantCapability`, `AssistantPolicy` |
| `Core/AssistantContext.swift` | `AssistantContextItem`, `AssistantAllowedContext`, `AssistantHubState`, `AssistantLimits` |
| `Core/AssistantActions.swift` | `AssistantActions`, `AssistantRequest`, `AssistantActionReport`, `AssistantRouter` |
| `Core/AssistantPrompt.swift` | `AssistantTurn`, `AssistantPrompt` |
| `Core/AssistantReply.swift` | `AssistantModelReply`, `AssistantFollowUp`, `AssistantExchange`, `AssistantReplyComposer` |
| `Core/AssistantConversation.swift` | The state machine |
| `Core/AssistantEngine.swift` | `AssistantEngine`, `AssistantToolbox`, and the protocols for the model, speech, and the hub |
| `Core/AssistantFailure.swift` | `AssistantFailure` and the mirrors of the framework errors |
| `Core/AssistantSettings.swift` | `AssistantSettings`, `AssistantPreferences` |
| `Core/AssistantAppearance.swift` | `AssistantPalette`, `EdgeGlow`, `AssistantLayout` |
| `Core/AssistantText.swift` | Folding, clipping, durations |
| `AppleIntelligenceGate.swift`, `AppleIntelligenceRequiredView.swift` | The gate and its screen |
| `FoundationModelResponder.swift`, `AssistantTools.swift` | The model session, its tools, and `ScriptedAssistantResponder` |
| `AssistantSpeech.swift` | Speech in and out |
| `AssistantEngine+Live.swift` | The engine the app uses, and `AssistantEngine.scripted` |
| `AssistantOverlayView.swift`, `EdgeGlowView.swift` | The overlay |
| `AssistantIntents.swift` | App Intents and `AssistantIntentHandlers` |
| `AssistantStrings.swift` | Text for failures, chips, and action results |
| `AssistantPreviews.swift` | Previews with a scripted engine |

`Core/` stands for `Sources/HomePadAssistantCore/`. The others are in `Sources/HomePadAssistant/`.

## What could not be verified here

- **Any answer from the model.** On the iPhone 18 Pro simulator `SystemLanguageModel.default`
  reports `available`, but a request fails inside the system's safety check with "Simulator is
  not supported". So streaming, guided generation, tool calls, and the error mapping were
  compiled against the SDK and never run. `SimulatorProbeTests` records this when
  `TEST_RUNNER_HOMEPAD_ASSISTANT_PROBE_FILE` names a file.
- **The error types at run time.** The failure above arrived as an `NSError` in the domain
  `FoundationModels.LanguageModelError`, not as a `LanguageModelError` value, so it maps to
  "Something went wrong". A device may deliver other failures the same way. The deprecated
  `LanguageModelSession.GenerationError` is not mapped.
- **Speech.** Microphone and speech permission prompts, on-device recognition, the end of
  speech, interruptions, and the synthesizer need a device and a person.
- **How the overlay looks.** No screenshot was taken, because the package is not in the app yet.
  That `ConcentricRectangle` picks up the display's corner radius at the root of a full-screen
  scene is taken from the SDK, not seen.
- **App Intents metadata.** The intents compile. Whether Shortcuts lists them depends on the app
  including `HomePadAssistantIntents`.
- **Speech recognition with `SpeechAnalyzer`.** The SDK's newer `SpeechAnalyzer` and
  `SpeechTranscriber` are not used. Their models are installed through `AssetInventory`, which
  downloads at the app's request, and HomePad makes no network calls of its own.
