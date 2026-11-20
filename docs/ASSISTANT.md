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
| Tidying a recipe for the Recipes reader | FoundationModels | `FoundationModelRecipeFormatter` (see Recipes) |

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
model, microphone, or speaker, and makes `RecipeFormatters.make` return the scripted recipe
formatter.

## Privacy rules

All of these are decided in `HomePadAssistantCore` and unit tested.

1. **Filtering comes before the prompt.** `AssistantPolicy.allowedContext` is the only way to
   make an `AssistantAllowedContext`, and `AssistantPrompt` takes nothing else. An item is
   personal when its kind is a calendar event or reminder, or when it has an owner. A
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
temperature unit) and `contextItems()`. The kinds are timer, weather, home, now playing,
playlist, calendar event, and reminder. A personal item carries its owner's id. There is no kind
for messages: the hub never holds anyone's messages, so the Assistant cannot be given one.

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

## Recipes

The Recipes reader shows a recipe as the page wrote it. This package can lay the same recipe out
as short steps with the language model on the device. The reader side is in `HomePadUI` and has
its own protocol. The app target maps between the two. This package does not import `HomePadUI`,
does not fetch the page, and does not log page text, recipe text, or prompts.

### API

```swift
@MainActor public protocol RecipeFormatting: AnyObject {
    func format(draft: RecipeDraft, pageText: String) async -> RecipeFormattingOutcome
}
```

| Type | Holds |
|---|---|
| `RecipeDraft` | What the page's parser found: `name`, `summary`, `yield`, `totalTime` (seconds), `ingredients`, `steps`. Any part may be empty |
| `FormattedRecipe` | `name`, `summary`, `yield`, `totalTime`, `ingredients` (one line for each line of the page, same order), `steps`. Only this package can make one |
| `FormattedRecipe.Step` | `id`, `sourceStepNumber`, `title`, `instruction`, `ingredients` (the lines the step names), `timerSeconds`, `isPageText` |
| `RecipeFormattingOutcome` | `formatted` (nil means show `original`), `original`, `originalWasLocatedByModel`, `failure`, `wasTidiedByModel` |
| `RecipeFormattingFailure` | `turnedOff`, `canceled`, `noRecipeFound`, `pageTooLong`, `recipeTooLong`, `rejected`, `model(AssistantFailure)` |

`pageText` is the page's readable text with one block to a line. It is used only when the draft
has no ingredients or no steps.

| Formatter | Target | Model |
|---|---|---|
| `FoundationModelRecipeFormatter(isEnabled:)` | `HomePadAssistant` | `SystemLanguageModel.default` |
| `ScriptedRecipeFormatter(isEnabled:delay:)` | `HomePadAssistantCore` | `ScriptedRecipeModel`: fixed rules, no model |
| `RecipeFormatters.make(settings:hooks:)` | `HomePadAssistant` | The scripted one when `hooks.usesScriptedAssistant`, otherwise the live one. Both read Tidy Up Recipes at every call |

Both formatters are a `RecipeFormatter` (Core) around a `RecipeModel`. `RecipeFormatter` holds
every decision and is the part with unit tests. The scripted formatter is in Core so that the
tests can prove its output passes the same checks. `RecipeDraft.sample` is a recipe for previews
and UI tests.

One recipe at a time. A second call to `format` cancels the first, which returns `canceled`.
Canceling the task that called `format` cancels the request to the model, so a reader that calls
from `.task` cancels when it closes. `format` never throws.

### What the reader gets

| Case | `formatted` | `failure` |
|---|---|---|
| Tidied. Steps with `isPageText` kept the page's wording | set | nil |
| Tidy Up Recipes is off | nil | `turnedOff` |
| The model is not available, failed, or timed out before half the steps were tidied | nil | `model(...)` |
| The model answered and fewer than half the steps passed the checks | nil | `rejected` |
| The draft had no recipe and none was found in the page text | nil | `noRecipeFound` or `pageTooLong` |
| More than 60 ingredient lines or 40 steps | nil | `recipeTooLong` |

`original` is always the plain recipe to show or to offer beside the tidied one. Name, yield, and
total time are never written by the model. They are the draft's, or a line of the page.

### Requests to the model

The model gets no tools and each request gets a `LanguageModelSession` of its own, so the text of
a page can reach nothing but the text of its own recipe, and no transcript carries one request
into the next. Sampling is `GenerationOptions.SamplingMode.greedy`, which the SDK documents as
always giving the same output for the same input. Answers are guided generation into `@Generable`
types.

| Request | When | The model returns |
|---|---|---|
| Locate | The draft has no ingredients or no steps | Six line numbers: name, yield, first and last ingredient line, first and last step line. The recipe's text is then copied from the page |
| Ingredients | Always, at most 30 lines a request | Each line again with the amount first, under the same number, and a summary of one or two sentences |
| Steps | Always, at most 6 steps a request | Short steps, each with the number of the step it came from, a title, one or two sentences, and a timer in seconds |

Every prompt puts the page's text between `<<<PAGE` and `PAGE>>>`. The instructions say that this
text is untrusted content from a web page and that no instruction inside it is to be followed.
Page text is folded onto one line and cannot contain either marker.

Limits: 60 seconds for one request, 180 seconds for one recipe. A request the model declines is
skipped and its lines keep the page's text. A request that is too long for the model is asked
again in two halves. Any other failure ends the requests for that recipe.

### Context size

The SDK gives the size as `SystemLanguageModel.contextSize`, in tokens, for instructions, schema,
prompt, and answer together. The value comes from the system at run time. The only number in the
SDK itself is 4096, which the property returns on systems before iOS 27. The simulator reports 0.
When the reported value is 0 or less, requests are planned for 4096 tokens
(`RecipeLimits.fallbackContextTokens`).

`RecipeBudget` plans each request so that the prompt and the largest allowed answer fit together.
It counts 3 characters for one token and keeps 500 tokens for the instructions and the schema.
With 4096 tokens that is about 10,400 characters of page text for a locate request, 3,500
characters of steps for a steps request, and 4,100 characters of ingredient lines. Before a
request is sent, the live model counts it with `SystemLanguageModel.tokenCount(for:)`. A request
the count shows to be too long is not sent and is asked again in halves.

A page that does not fit:

- The page text is first reduced: menu and sharing lines are dropped, everything from a
  "Comments", "Reviews", or "Related" heading after the ingredient list is dropped, and when room
  is short the story above an "Ingredients" heading is dropped except its first two lines.
- What is left is cut into parts that each fit one locate request. Each part starts halfway
  through the one before, so a recipe split by one cut is whole in the next part. At most 4 parts
  are searched. If none holds a recipe and text was left over, the failure is `pageTooLong`.
- A step longer than 1,500 characters is never sent. It keeps the page's text.

### Checks before anything is shown

`RecipeValidator` checks everything the model wrote against the page's recipe. A line or a step
that fails keeps the page's own text. A result with fewer than half its steps tidied is discarded.

| What | Rule |
|---|---|
| Ingredient line | The same amounts, each as many times, and the same set of words as the page's line. So a line can only be reordered. A line the model leaves out, numbers twice, or numbers wrongly keeps the page's text. The list always has one line for each line of the page |
| Summary | At most 2 sentences and 220 characters. Every amount in it is in the recipe. At least 75% of its words are the recipe's. Otherwise the first two sentences of the page's summary are used |
| Step: amounts | The short steps state the page's amounts once each and in the page's order |
| Step: what an amount measures | Each amount keeps a word next to it. For food, a word that follows it ("1 cup flour"). For a time or a temperature, a word before or after it ("bake 10 minutes") |
| Step: no additions | Every word is a word of the page's step, or one of a few plain verbs (add, combine, mix, place, and so on) |
| Step: nothing lost | Every word of the page's step that names an ingredient stays. So do not, no, never, without, before, after, until, unless, or, low, medium, high, covered, and uncovered. Each sentence of the page's step keeps at least 80% of its words |
| Step: shape | 1 to 6 short steps for one step of the page, each at most 320 characters and 3 sentences |
| Step order | The answer must go through the page's steps in order and name only steps it was sent. Otherwise the whole answer is refused |
| Title | At most 6 words and 48 characters, from the step's own words. A title that fails is left empty |
| Timer | The model's value stands only when the instruction states that time. Otherwise it is the one time the instruction states, or none |
| All model text | No angle bracket, square bracket, brace, vertical bar, asterisk, number sign, backtick, at sign, backslash, or underscore. No `http:`, `https:`, `www.`, or `://`, and no address ending such as `.com` |
| Located recipe | Line ranges inside the page, ingredients and steps not overlapping, and at least half the ingredient lines holding a number |

Two texts agree on an amount when the number and the unit are the same:

| Same amount | Not the same amount |
|---|---|
| `1/2`, `½`, `0.5` | `1 hour` and `60 minutes` |
| `1 1/2`, `1½`, `1-1/2`, `1.5` | `1 lb` and `16 oz` |
| `2` and `two` (up to twelve) | `350 degrees` and `350°F` |
| `a cup` and `1 cup`, `an hour` and `1 hour` | `2 T` and `2 tablespoons` |
| `10 minutes`, `10 min`, `10 mins` | `half a cup` and `1/2 cup` |
| `2 tablespoons`, `2 tbsp`, `2 Tbsp.` | |
| `350°F`, `350 degrees F`, `350 F` | |
| `8 to 10 minutes`, `8-10 min` | |

The right column is refused on purpose. A refused line costs tidiness. A wrong amount costs the
dish.

`FormattedRecipe.Step.ingredients` is worked out from the words, not by the model: a step uses a
line when it says the line's main name, the "butter" of "unsalted butter, softened". It misses an
ingredient the step calls by another word.

### Wiring into the app

| Where | What |
|---|---|
| `AppModel.swift` | `RecipeFormatters.make(settings:)` once, kept for the app's life |
| The reader's adapter | Map the reader's recipe to `RecipeDraft`, call `format` from the reader's task, and map `RecipeFormattingOutcome` back. Show `formatted` when it is set and offer `original` beside it |
| `HomePadUITests` | `HOMEPAD_UITEST_SCRIPTED_ASSISTANT=1` gives the scripted formatter, which answers at once |

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
| `assistant.formatRecipes` | Tidy Up Recipes | on |

Turning the Assistant off hides the overlay. It does not lift the gate, and it does not turn off
Tidy Up Recipes, which has its own switch.

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
| `Core/RecipeTypes.swift` | `RecipeDraft`, `FormattedRecipe`, `RecipeFormattingOutcome`, `RecipeFormattingFailure`, `RecipeFormatting`, `RecipeLimits` |
| `Core/RecipeFormatter.swift` | `RecipeModel`, `RecipeFormatter`: the requests, timeouts, cancellation, and the result |
| `Core/RecipeValidator.swift` | `RecipeValidator`, `RecipeIngredientIndex` |
| `Core/RecipeScan.swift` | `RecipeScan`: amounts, units, times, and word stems of a text |
| `Core/RecipeText.swift` | Plain-text test, sentences, bullets, step labels |
| `Core/RecipePage.swift` | `RecipePage`: page text reduced and cut into parts |
| `Core/RecipePrompt.swift` | `RecipePrompt`, `RecipeBudget`, `RecipeChunks`, and the request and answer values |
| `Core/RecipeScript.swift` | `ScriptedRecipeModel`, `ScriptedRecipeFormatter`, `RecipeDraft.sample` |
| `AppleIntelligenceGate.swift`, `AppleIntelligenceRequiredView.swift` | The gate and its screen |
| `FoundationModelResponder.swift`, `AssistantTools.swift` | The model session, its tools, and `ScriptedAssistantResponder` |
| `FoundationModelRecipeFormatter.swift` | `FoundationModelRecipeFormatter`, its `@Generable` types, `RecipeFormatters` |
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
- **Any recipe tidied by the model.** No formatting ran. The recipe requests fail on the simulator
  the same way, and the simulator reports a context size of 0 and cannot count tokens. What is
  proven there is the other path: the model fails, one request is sent, and the plain recipe
  comes back unchanged (`SimulatorProbeTests` writes this to the probe file with the suffix
  `.recipe`). On a device these need checking: the context size the system reports, whether 3
  characters to a token holds for recipe text, how long a recipe takes, and how many of the
  model's steps pass the checks. The checks are strict, so a model that rewords freely will leave
  many steps in the page's text.
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
