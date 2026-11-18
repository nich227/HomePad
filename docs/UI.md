# HomePadUI: the hub shell and the companion shell

`Packages/HomePadUI` draws the HomeView-style experience on the iPad hub and the companion on
the iPhone. Both adapt to the space they get, including the two displays of a folding iPhone
(see "Sizes and folding displays"). It has two targets:

| Target | What it holds |
|---|---|
| `HomePadUICore` | Pure logic, unit-tested on the iOS simulator: clock math, time text, the timer state machine, alarm scheduling, layouts and their store, the app and widget catalog with visibility rules, night mode, the recipe parser, Flow face math, the canvas layout, the rules for sizes and folds, and `UISettings`. |
| `HomePadUI` | SwiftUI views and the services behind them (HomeKit, Music, camera, WeatherKit, Photos). |

## How the app target uses it

```swift
@State private var session = HouseholdSession(store: profileStore)
@State private var settings = HomePadSettings()
@State private var environment = HubEnvironment.live()
@State private var navigator = HubNavigator()

HomePadRootView(
    session: session,
    settings: settings,
    slots: HubFeatureSlots(
        beam: { AnyView(BeamInboxView()) },
        messages: { AnyView(MessagesView()) },
        projectedApps: { AnyView(ProjectedAppsView()) },
        people: { AnyView(PeopleView()) },
        recognitionIndicator: { AnyView(RecognitionChip()) },
        pairing: { AnyView(PairingView()) },
        deviceUnlock: HubDeviceUnlock(
            isOffered: { session.canConfirmWithDeviceBiometrics },
            unlock: { await deviceBiometrics.confirm() }
        )
    ),
    environment: environment,
    navigator: navigator,
    facePosition: { faceTracker.normalizedPosition },
    ambientLight: { faceTracker.ambientLight },
    hubSummary: summaryReceiver.summary,
    onHubSummaryChange: { summary in Task { await broadcaster.publish(summary) } },
    onWelcomeFinished: { model.startRecognition() }
)
```

- Call `settings.register(UISettings.descriptors + GeneralSettings.descriptors + ...)` at launch.
- `HubEnvironment.live()` and `HubNavigator()` must be created once and kept, not built in `body`.
- When a page arrives from a companion, call `navigator.presentBeam()`. The beam slot then covers
  the whole screen, after a short arrival animation, until it is closed.
- When a beamed page is a recipe, call `navigator.openRecipe(url, context:)` to open it in the
  recipe reader.
- Start the camera in `onWelcomeFinished`, not at launch. It is called once, when the first-run
  welcome has been dismissed or was never needed. See "Permission prompts" below.
- `HubSummaryBroadcaster` and `HubSummaryReceiver` carry "what the hub is showing" over any
  `PeerChannel` on the channel named `HubStatusSummary.channel`.

### Slots

`HubFeatureSlots` is a struct of `@MainActor () -> AnyView` closures. Each has a placeholder.

| Slot | Where it appears on the hub | On the companion |
|---|---|---|
| `beam` | Beam app on the Home Screen, and the full-screen takeover | Beam section |
| `messages` | Messages app. Personal: hidden for guests, greyed out until a face unlocks it | not shown |
| `projectedApps` | iPhone Apps app. Personal, same rule as Messages | Apps section |
| `people` | People app, only while Setup Mode is on | People section, only while Setup Mode is on |
| `pairing` | Pairing app, only while Setup Mode is on | People section, only while Setup Mode is on |
| `recognitionIndicator` | In the black beside the canvas, under the profile avatar. In the Home Screen header only when the canvas has no margin | not shown |

On the companion a section is a tab in a compact width and the trailing column in a regular
width. The `beam`, `people`, and `pairing` slots are placed inside a `NavigationStack`, so a slot
view sets a title and does not bring its own stack. The `projectedApps` slot fills its section
and brings its own. The companion puts no custom view in a toolbar, because the system cannot
move a custom view into the bars it draws down the side of a folding iPhone.

Slot apps are drawn by `SlotScreen` inside the square canvas: a title and a round close button
above, a black background, and the dark color scheme. The slot's text is stepped up through
Dynamic Type (`SlotTextScale`) so ordinary text styles read from across a room; the view is not
scaled. A slot view should lay out for a square of any size, use text styles and not fixed point
sizes, and put an empty state in the middle of the space and not inside a `List` row.

### Touch ID unlock

On an iPad without Face ID hardware, the camera can match a member but cannot prove a live face.
That match personalizes the hub and leaves personal content locked. The device's own biometrics
are the second step.

```swift
public struct HubDeviceUnlock {
    public var isOffered: @MainActor () -> Bool
    public var unlock: @MainActor () async -> Bool
    public init(isOffered: @escaping @MainActor () -> Bool, unlock: @escaping @MainActor () async -> Bool)
}

// HubFeatureSlots
public var deviceUnlock: HubDeviceUnlock?   // trailing init parameter, nil by default
```

While `isOffered()` is true and the active profile is personalized but locked, the shell shows
"Unlock with Touch ID" (the `touchid` symbol) in four places:

- A round button under the avatar beside the canvas (`hub.deviceUnlock`).
- Each locked personal app icon: the lock badge becomes a Touch ID badge and the icon accepts a tap.
- Each locked personal widget: the tile shows the symbol and "Unlock with Touch ID".
- A capsule in the profile switcher (`switcher.deviceUnlock`).

A tap on a locked app or widget calls `unlock()`. When it returns true and the app is now
visible to the person, the app opens. The decisions are in `VisibilityPolicy` (Core):
`tapAction(for:context:isDeviceUnlockOffered:)` returns `.open`, `.requestUnlock`, or `.none`;
`appToOpen(afterUnlock:requested:context:)` says what opens afterward; and
`showsDeviceUnlock(context:isDeviceUnlockOffered:)` gates the affordance. With the hook nil or
not offered, a locked item is inert, as before. After a successful unlock the session is in the
same state as after a live face match, so every rule keyed on a face match applies, scenes
included.

## Settings

The app has no settings screens. Every preference is read through `HomePadSettings` from keys
declared in `UISettings` (`HomePadUICore/UISettings.swift`), and the app never writes one. Where
someone would look for settings (the profile switcher, the note shown when nobody is set up, and
the empty states that need a permission or a value) there is one "Open Settings" button that
opens the system Settings app. On the hub it is a wide glass capsule (`HubSettingsButton`). The Settings icon on the Home Screen does the same.

Face options are household-wide, because a Settings bundle is static. What is per person is
state, kept in the `LayoutStore`: the last face they rested on and the order of their Home Screen
icons and widgets.

Setup Mode (`GeneralSettings.setupMode`) gates the `people` and `pairing` slots. With Setup Mode
off and nobody enrolled, the Home Screen and the profile switcher show a short note that points
to Settings.

## The canvas

HomeView's screen is square and an iPad's is not. `CanvasLayout` places a square canvas, with
HomeView's rounded corners, on true black, scaled to the shorter side of whatever space the app
has (full screen, Split View, Stage Manager). Everything is sized in hundredths of the canvas
side, so faces keep their proportions at any size.

`ui.display.canvas` chooses what happens to the rest of the screen:

- **Square (like HomeView)**, the default: the canvas is centered and the rest stays black.
- **Fill the screen**: the canvas moves to the leading edge (or the top, in portrait) and a second
  column shows up to four Home Screen widgets (timers when one is running, now playing, weather,
  home, clock), drawn at their Home Screen proportions and scaled. `SidePanelGrid` picks how
  many and in what grid: three in one column beside a large iPad's canvas.

### Status beside the canvas

Nothing about who is in front of the hub is drawn on a face. `CanvasLayout.status` gives a frame
in the black around the square: the full height beside it in landscape, a strip above it in
portrait, and a strip above the second column in fill mode. `BezelStatusView` draws there:

- The active profile's avatar and name, or Guest. A tap opens the profile switcher (`hub.profile`).
  On the Home Screen the header already shows both, so they are left out here.
- The `recognitionIndicator` slot, scaled down when it is wider than the space.
- The Touch ID button, while it is offered.
- One round button that goes to the Home Screen from a face, and back to the face from the Home
  Screen (`hub.showHomeScreen`, `hub.showFace`).

In the narrow strip above the second column the buttons share the width and the name is left out.
When the app's space is square and there is no margin (`status` is nil), the avatar is in the
Home Screen header only, and small chevrons at the bottom of the canvas move between the face
and the Home Screen.

## Sizes and folding displays

Nothing here checks for a device model. Layout follows the size class, the size of the
container, and what the system reports about the display. That covers an iPhone, an iPad in any
window size, and iPhone Duo, which has a compact-width outer display (about 466 by 678 points)
and a regular-width inner display (about 626 by 890 points) that folds across its middle. The
rules are in `HomePadUICore/AdaptiveLayout.swift`.

### Companion

`CompanionLayoutPolicy.arrangement(isRegularWidth:width:)` picks one of two arrangements. One
selection (`CompanionSection`) serves both, so opening and closing the device keeps the place.

| Width | Arrangement | Container |
|---|---|---|
| Compact: an iPhone, the outer display of iPhone Duo in either orientation | Four tabs: Hub, Beam, Apps, People | `TabView` |
| Regular and at least 560 points: the inner display in either orientation, an iPad | Two columns. Leading: what the hub is showing, then the list of sections. Trailing: the chosen section | `NavigationSplitView`, balanced |

- The hub's status is always visible in the leading column, so Hub is not in its list. With
  the Hub tab selected, the trailing column shows Beam, and the selection is kept for the way
  back to tabs.
- The columns ask for widths in proportion to the container
  (`CompanionLayoutPolicy.sidebarWidth(forWidth:)`, `minimumDetailWidth`). These are
  preferences. Without them the split view on the iPad mini stand-in laid the leading column
  over the content at 626 points; with them it shows both side by side.
- The system places the bars. On iPhone Duo's outer display it draws tab bars and toolbars
  down the side, and the companion does not opt out anywhere (`toolbarVerticalBehavior` is not
  used). The package presents no sheets, so `presentationPlacement` is not used either.
- When the inner display is partly folded, the split view gives each column one side of the
  fold. That is the system's behavior for `NavigationSplitView`; the companion adds nothing.
  Apple's guidance is to keep an `ArrangementView` out of a split view, so none is used here.
- A section's own state, such as a link typed into Beam, starts again when the arrangement
  changes between tabs and columns, because each arrangement builds its own copy of the section.

### Hub

The hub is two panes: the canvas, and the chrome around it (who is in front, the way between
the face and the Home Screen, running timers, and the widgets of the second column).

| iOS | Container | Display flat | Display partly folded |
|---|---|---|---|
| 27.1 and later | `ArrangementView` with the `.overlay` style. The chrome is the primary view and the canvas the secondary | The chrome lies over the canvas. Each draws only in its own part of the screen, placed by `CanvasLayout`, as before | The system gives each pane one side of the fold: the canvas leading or on top, the chrome trailing or below |
| 26.0 to 27.0 | `ZStack` | The same | Not applicable: no folding device runs these versions |

Each pane measures itself against the whole container (`HubPanePolicy.placement`). A pane with
less than three quarters of the area has been given a side of its own. Then:

- The canvas pane draws the largest square that fits its side.
- The chrome pane fills its side (`ChromePanelLayout`): the status across the top, the timer
  strip under it, then the widgets in the grid that suits the space (`SidePanelGrid`), two by
  two on half of the inner display. The timer strip leaves the face while it is shown here.

With the display flat the canvas scales as on any screen. The status sits in the strip above
the canvas in portrait and in the column beside it in landscape, at the inner and the outer
sizes alike, and falls back to the in-canvas controls when the space is exactly square.

- Round buttons never get smaller than 44 points (`HubMetrics.minimumTouchSide`), however
  small the canvas.
- The status keeps clear of the safe area and of anything that covers the display. On iOS
  27.1 and later it asks the `GeometryProxy` for `reservedRegions(kind: .occlusion)`, which is
  where the outer display's camera is reported, and moves in from the nearest edge
  (`CanvasFrame.insets(clearing:)`). The canvas itself still runs to the edges of the display.
- The second column picks its grid from the space: one column of three beside a large iPad's
  canvas, as before, and other grids in smaller spaces.

### What is and is not verified

No iPhone Duo simulator runs on this machine. The UI tests frame the whole app to the Duo's
sizes on the iPad mini simulator (`HOMEPAD_UITEST_VIEWPORT`) and, for the hub, place the two
panes in halves the way the documentation describes a folded overlay arrangement
(`HOMEPAD_UITEST_FOLD`). So the layouts at those sizes and the contents of each pane are seen.
`ArrangementView` itself runs on the iOS 27.2 simulators with the display flat, and the whole
hub walkthrough passes through it. These are not seen and come from Apple's documentation:
the system's bars down the side of the outer display, the real position and behavior of the
fold, `ArrangementView` and `NavigationSplitView` in a folded pose, the occlusion that
`reservedRegions` reports for the cameras, and the size classes a real Duo reports.

## Faces

Swipe left or right to change faces, or use the arrow keys. Swipe up, press the up arrow, or tap
the round button beside the canvas for the Home Screen. A face carries no chrome of its own
except the timer capsule while a timer runs. Each face has two densities and animates between them:
`Proximity.far` shows less, larger; `.near` shows more. `ui.display.adaptiveDetail` turns this
off, which keeps the detailed layout.

| Face | Far | Near | Reference |
|---|---|---|---|
| Modular | Date and analog clock, large | Adds now playing and weather, four widgets | `homeview-reference.jpg`, `newsroom-collection-of-faces.jpg` |
| Photos | Photo with four very tall translucent digits | Adds the date | `product-faces-endframe.jpg`, `newsroom-collection-of-faces.jpg` |
| Weather | Condition, time, very large temperature | Adds high and low and a row of four details | `newsroom-collection-of-faces.jpg` |
| Home Modular | Thermostat, clock, four tiles without subtitles | Adds room names | `product-dashboard.jpg`, `newsroom-lifestyle-living-room.jpg` |
| Calendar | Month, time, very large day number, weekday | The month grid alone, with today circled | `newsroom-collection-of-faces.jpg` |
| Flow | Liquid digits on a pink and blue field | Adds the date | `newsroom-collection-of-faces.jpg` |
| Analog | Numerals and hands | Adds the second hand and "WED 1" | `newsroom-collection-of-faces.jpg` |
| Fade | Numerals close to the minute hand | Numerals fade over a wider arc | `newsroom-collection-of-faces.jpg` |
| Digital | Date and a larger time | Adds AM or PM and two small widget spots | none |
| Home Camera | Up to nine camera tiles | Adds camera names | none |
| Rainbow | Six stripes and the time | Adds the date | our own |

### What was matched to a screenshot

- **Modular**: the two by two arrangement; "Wed" in the accent color next to "Apr"; the very
  large condensed day number; the round dial with twelve numerals; the music tile with artwork,
  uppercase title, artist, and a Play pill; the weather tile with city, large temperature,
  condition, and "H: L:".
- **Photos**: four tall, condensed, translucent digits across the full width with a gap in the
  middle for the subject, and the subject in front of the digits. The subject is cut out on the
  device with Vision's foreground instance mask.
- **Weather**: condition and high and low at top left, time at top right, the temperature very
  large and translucent, and four details across the bottom.
- **Home Modular**: a three by three grid of glass tiles with one two by two thermostat tile
  (large number, down and up chevrons, name and room), a tile-less clock with hour ticks at top
  right, and four small tiles with icon, bold name, and lighter room name.
- **Calendar**: the light card, red month and time, navy weekday letters, blue day numbers, grey
  days outside the month, and today in a navy circle. The very large red day number is the far
  layout. Apple's image draws it behind the grid as well; here the near layout shows the grid
  alone, because the number made the dates hard to read.
- **Analog**: a solid green dial, four oversized thin numerals that run off the edges, white hands
  with a thin stem and a rounded bar, and "WED 1" at the bottom left.
- **Fade**: a single-color dial, tone-on-tone numerals rotated around the dial and fading away
  from one side, dark hands, and a colored second hand. Gray with a blue second hand is the
  default; Rose matches the dusty pink in `newsroom-collection-of-faces.jpg`.
- **Flow**: digits as soft liquid shapes in two rows on a pink and lavender field, in blue and
  pink.
- **Timer** (`newsroom-timer.jpg`): tick marks around a rounded square that go dark as time runs
  down, orange on black, large white digits, and the timer's length in orange capitals.
- **Music** (`guide-music-player.png`): a dark blur behind, round glass buttons in the top
  corners, large centered artwork with rounded corners, the title and artist over its lower
  edge, a thin white progress bar with elapsed and remaining times, and previous, pause, next.
- **Recipe cover** (`guide-recipe.png`, `newsroom-cooking.jpg`): full-bleed photo, round glass
  close button, time at top right, bold title, "source, time, servings" line, and two wide glass
  capsules, Ingredients and Start Cooking.
- **Home Screen** (`guide-home-screen-apps.png`, `product-multiuser-endframe.jpg`,
  `newsroom-user-recognition.jpg`): the blurred face behind, the uppercase greeting and name, the
  round avatar at top right, four columns of large rounded icons with labels, and two by two
  widget tiles in the same grid.
- **Home app** (`newsroom-home-touch.jpg`): a three-column grid of rounded tiles with a tile-less
  clock in the first cell. The grid follows the screenshot. The colors do not: the app is dark
  like the rest of the shell, and a tile is lit when its accessory is on.
- **First run** (`guide-hello.png`): a warm red, pink, and yellow shape on cream behind a hello
  animation, with two wide capsules, Not Now and Add People. The capsules are solid, because
  glass on cream loses a white label.

### What was approximated

- **Typefaces.** Only system fonts are used. The tall digits use SF at compressed width stretched
  vertically; HomeView's digit shapes are narrower and have a glass edge. The Flow face draws
  blurred, thresholded SF Rounded digits and loose drops, which gives liquid shapes but not
  HomeView's exact glyphs.
- **Wallpapers and photos.** No Apple artwork is copied. Home Modular uses drawn shapes in the
  active profile's color; the Weather face draws blurred ellipses for clouds; the Photos face
  shows a tinted field and a silhouette until photos are chosen.
- **App icons.** Icons are SF Symbols on a rounded square in one of the six rainbow colors or
  grey. They follow the size, corner radius, and label style of the screenshots, not the artwork.
- **Digital and Home Camera.** No screenshot showed these, so they follow the written
  descriptions: a large time with two small spots, and a grid of up to nine cameras.
- **Fade.** The review screenshot could not be fetched (see below). The gray dial and blue second
  hand come from the written description; the layout comes from the pink Fade face in Apple's
  image. Which side the numerals cluster on is tied to the minute hand here, which is a guess.
- **Photos digits.** The four digits are drawn from strokes (`TallDigits` in Core) with one
  uniform width and filled as a single translucent shape. HomeView's digits have a glass edge
  and refract the photo; these do not.
- **Recipe steps, ingredient list, timer controls, the profile switcher, alarms, mirror.** No
  screenshot showed these screens. They reuse the visual pieces that are shown: round glass
  buttons, wide glass capsules, the rounded-square tiles, and the orange timer accent.
- **Empty states.** No screenshot showed an app with nothing in it. Every native app uses one
  layout (`HubEmptyState`): a large symbol, a title, one line of explanation, and at most one
  action, centered in the canvas.
- **Music.** The lyrics, queue, and "more" buttons in the screenshot are left out because the
  system music player gives a third-party app nothing to put behind them. The speaker button is
  the system route picker.
- **Snoopy and the memory-style Photos face** are not built. Snoopy is licensed artwork.

### References

In `design/reference/` (plus `design/homeview-reference.jpg`):

| File | Shows |
|---|---|
| `newsroom-collection-of-faces.jpg` | Thirteen faces |
| `newsroom-lifestyle-living-room.jpg` | Home Modular, blue |
| `newsroom-timer.jpg` | Timer |
| `newsroom-cooking.jpg`, `guide-recipe.png` | Recipe cover |
| `newsroom-home-touch.jpg` | Home app grid, light |
| `newsroom-apple-podcasts-lyrics-apple-music.jpg`, `guide-music-player.png` | Media player |
| `newsroom-user-recognition.jpg`, `product-multiuser-endframe.jpg`, `guide-home-screen-apps.png` | Home Screen, greeting, avatar |
| `product-dashboard.jpg` | Home Modular, close up |
| `product-faces-endframe.jpg`, `product-faces-enhanced.png` | Photos face, faces |
| `guide-hello.png` | Hello screen |
| the remaining `newsroom-*` and `product-*` files | Downloaded for context, not studied in detail |

Not fetched: every `media.appleinsider.com/gallery/...` image returned HTTP 403 from a bot
challenge, so the review gallery (app view, app icons, Flow, Fade, account setup, podcast player,
recipe timers, mirror, FaceTime, doorbell) was not seen. `support.apple.com/guide/apple-homeview`
returned 404, so the guide's chapters were not followed; the four guide images named in the task
did download.

## Home Screen

Swipe up from a face. It shows the greeting, the active profile (or Guest), and a four-column
grid of icons and two by two widgets, packed by `HomeGridPacker`. Drag an icon or widget onto
another to reorder; the order is saved per profile. Pull down past the top, tap the round button beside
the canvas, or press Escape to go back to the face.

Icons sit in `HomeGridLayout`, which gives each icon and widget its packed cell. A widget starts
on an even column, so two widgets or a widget and a block of four icons share a row.

Who sees what is decided by `VisibilityPolicy`:

| Access | Apps | Widgets | Guest | Profile picked by hand | Face recognized |
|---|---|---|---|---|---|
| guest | Clock, Timers, Home, Music, Mirror, Recipes, Weather, Beam, Settings | Clock, Calendar, Weather, Timers, Now Playing, Home, Thermostat, Camera, Photo | shown | shown | shown |
| member | Alarms, Photos | Next Alarm | hidden | shown | shown |
| personal | Messages, iPhone Apps | Messages | hidden | greyed out with a lock badge, cannot open. While Touch ID is offered, a tap asks for it | shown |
| setup | People, Pairing | none | only in Setup Mode | only in Setup Mode | only in Setup Mode |

When the person in front of the hub changes, an open app they may not see closes at once
(`HubNavigationState.audienceChanged`). Tapping the avatar opens the manual switcher, which calls
`HouseholdSession.switchManually` and so never unlocks personal content.

## Permission prompts

The hub asks for a permission when the person first reaches the thing that needs it, and never
on the welcome.

| Prompt | Appears |
|---|---|
| Camera | After the welcome is dismissed, or at launch when no welcome is due. The app starts face recognition from `onWelcomeFinished`. |
| HomeKit | The first time Home Modular or Home Camera is the face in front, a home widget scrolls into view, or the Home app opens. |
| Apple Music | The first time a now playing tile is on the face in front or scrolls into view, or the Music app opens. |
| Photos | Only with the Shared Album source, the first time the Photos face is in front. The photo picker needs no permission. |

Views start a service with the `startsOnFirstUse` modifier, which waits for `\.hubMayPrompt`.
That value is false while the welcome is up. In the face pager it is true only for the face in
front, because neighboring faces are built ahead of time. Home Screen widgets start when they
scroll into view.

## Apps

| App | Notes |
|---|---|
| Clock | Analog and digital time, date, next alarm. |
| Timers | Any number of named timers from a three by three grid of presets. `TimerEngine` is the state machine; `TimerCenter` runs it, saves it, and rings. A started timer opens full screen with pause and delete under the time. Running timers show as a glass capsule on every face. A finished timer covers the canvas until stopped. |
| Alarms | One-time or daily alarms. The new alarm's time is set with large up and down buttons for the hour and for the minute, in steps of five minutes (`AlarmTimeDraft`). Alarms ring while the app is in front. |
| Home | Scenes, accessories on and off, brightness from the tile's context menu, thermostat target, and cameras through `HMCameraView` (snapshots in tiles, a live stream when opened). A guest can lock a door but not unlock one. Scenes: see below. |
| Music | Now playing and transport through `MPMusicPlayerController.systemMusicPlayer`. |
| Mirror | Front camera, full view or zoomed. |
| Recipes | Paste or beam a link. `RecipeParser` reads schema.org Recipe JSON-LD from the page's HTML; the reader shows a cover, an ingredient checklist, and one step at a time with a timer button for any duration the step mentions. |
| Weather | WeatherKit behind `WeatherProviding`. Off until a city and coordinates are entered in Settings. |
| Photos | The system photo picker. Chosen photos are copied into the app's storage. |

### Who may run a scene

A scene can do anything its owner put in it, including unlock a door. Only a household member
the hub has recognized by face may run one: `HomeControlPolicy.mayRunScenes(activation:profiles:)`
is true only for `.face` with an enrolled profile. A guest and a profile picked by hand are
refused. A member confirmed by Touch ID counts, because the session then holds a face
activation. Scenes are not hidden from everyone else. Every scene tile, in the Home app and on
Home Modular, is dimmed with a lock badge and "Members only", and the Home app adds one line
that says why (`home.scenesLocked`). A tap on a locked scene does
nothing, and the service is not called.

Services sit behind protocols (`HomeService`, `MusicService`, `CameraPreviewService`,
`WeatherProviding`, `RecipePageLoading`) and `HubEnvironment.preview()` supplies stand-ins, so
every view previews without hardware.

## Night mode

`NightSchedule` and `NightModePolicy` decide when the hub shows a dim red clock: inside the
window set in Settings, and, with "Follow Room Light" on, whenever the room is dark and never
while it is lit. The room light comes from the optional `ambientLight` provider. The shell also
lowers the screen brightness and restores it afterward. A tap wakes the hub for 30 seconds.

## Animation

Lottie animations from `HomePadAnimations` mark single moments: `hello` on first run, `timerDone`
when a timer finishes, `presencePulse` around the avatar beside the canvas while someone is in view,
`beamIncoming` when a page takes over the screen, and `listening`, `pairing`, and `faceScan` in
empty states. Everything that follows data continuously is SwiftUI: clock hands, the Flow face
(`TimelineView`, `Canvas`, `MeshGradient`), and the change between far and near layouts. Reduce
Motion stops the sweep and the Flow drift; Reduce Transparency swaps glass for solid fills.

## What a third-party iPad app cannot do

Each line was checked against the iOS 27.2 SDK in Xcode 27.2.

| HomeView behavior | Status | Checked |
|---|---|---|
| Always-on, locked to one app | Not possible from inside the app. The device must be put in Guided Access, or be supervised for Single App Mode. | The only API is `UIAccessibilityRequestGuidedAccessSession`, which succeeds only on a supervised device that allows it. The kiosk package handles this. |
| Showing other apps' widgets | Not possible. Widgets here are the app's own views. | WidgetKit's interface has no type for hosting a widget from another process. |
| Siri and Apple Intelligence on screen | Not possible. An app can only offer its actions to Siri through App Intents. | `AppIntents.framework` is the only Siri surface in the SDK; there is no API to present or query the assistant. |
| Find My | Not possible. | The SDK has no Find My framework. |
| Ambient light sensor | Not available. The shell takes a hint from the app instead. | `UIScreen` and `UIDevice` expose no ambient light reading; `SRAmbientLightSample` is in SensorKit, which is limited to approved research studies. |
| Knowing how far away someone is | The shell does not measure it. `HouseholdSession.proximity` is driven by the face package. | n/a |
| Controlling other apps' audio | Only the Music app's player is reachable. | `MPMusicPlayerController.systemMusicPlayer` controls Music; there is no public API for another app's now playing session. |
| FaceTime, Intercom, doorbell takeover | Not built. | Out of scope for this package. |
| Alarms and timers that ring while the app is not in front | Not built. AlarmKit is in the SDK and could do it; it needs its own authorization and UI. | `AlarmKit.framework` exists; this package does not use it. |

## Info.plist keys and entitlements

| Key or entitlement | Needed for | Required |
|---|---|---|
| `NSHomeKitUsageDescription` and the HomeKit capability (`com.apple.developer.homekit`) | Home app, Home Modular, Home Camera | For home features. |
| `NSCameraUsageDescription` | Mirror | For Mirror. |
| `NSAppleMusicUsageDescription` | Music now playing | For Music. |
| `NSPhotoLibraryUsageDescription` | Photos face with the Shared Album source | Only for that source. The photo picker needs no key. |
| WeatherKit capability (`com.apple.developer.weatherkit`) | Weather | Optional. Without it weather shows as unavailable. |
| `com.apple.developer.avfoundation.multitasking-camera-access` | Mirror in Split View or Stage Manager | Optional. The session enables multitasking camera access when the device supports it. |

Each service checks that its usage description is in Info.plist before it asks for access, and
reports "not available" when the key is missing, so a missing key does not end the app.

No background modes. No network listener. Recipe pages are fetched over HTTPS with an ephemeral
session; plain HTTP pages are blocked by App Transport Security unless the app adds an exception.
State is stored under `Application Support/HomePad/UI` (layouts, timers, alarms, chosen photos);
none of it is a secret, and nothing is logged.

## UI tests and screenshots

`HomePadUITests` walks the app in the simulator and saves a screenshot at each stop to
`design/screenshots`. Each simulator runs its own tests and skips the rest:

| Command | Runs |
|---|---|
| `Scripts/ui-walkthrough.sh` (iPad Pro 13-inch) | `HubWalkthroughTests`: the hub |
| `Scripts/ui-walkthrough.sh "iPhone 18 Pro"` | `CompanionWalkthroughTests`: the companion's tabs |
| `Scripts/ui-walkthrough.sh "iPad mini (A20 Pro)"` | `DuoWalkthroughTests`: the companion and the hub framed to the sizes of iPhone Duo's displays |
 Controls are found by accessibility identifier. A
container must not carry an identifier, because it replaces the identifiers of the controls
inside it.

The tests put the app in a known state through launch environment variables. `HubTestHooks`
(Core) parses them in one place. Every hook is off unless its variable is set, debug builds
alone read them, and none is a preference.

| Variable | Effect |
|---|---|
| `HOMEPAD_UITEST_EPHEMERAL=1` | Layouts, timers, alarms, and photos stay in memory. |
| `HOMEPAD_UITEST_SAMPLE=1` | A sample household, home, music, weather, and recipe page stand in for the real services. Implies ephemeral. On the iPhone, a sample hub summary. |
| `HOMEPAD_UITEST_AUDIENCE=guest\|manual\|recognized` | Who is in front of the hub: nobody known, the first profile picked by hand, or the first profile recognized by face. |
| `HOMEPAD_UITEST_PROXIMITY=far\|near` | How close they are. |
| `HOMEPAD_UITEST_CANVAS=fill` | The fill layout for this launch, whatever Settings says. |
| `HOMEPAD_UITEST_NIGHT=1` | The night clock, whatever the schedule says. |
| `HOMEPAD_UITEST_SKIP_WELCOME=1` | No first-run welcome. |
| `HOMEPAD_UITEST_ROLE=hub\|companion` | The role for this launch, whatever the device and Settings say. |
| `HOMEPAD_UITEST_VIEWPORT=626x890` | The whole app framed to this size in points, centered on black, with the size classes a display of that size reports: regular width when the shorter side is at least 600 points, regular height from 480 points. |
| `HOMEPAD_UITEST_FOLD=1` | Hub only. The two panes in halves with a gap between them, as if the display were partly folded. |
| `HOMEPAD_UITEST_DEVICE_UNLOCK=1` | A camera match without a liveness proof is waiting and Touch ID is offered. A tap on the affordance confirms it. The hook stands in for the `deviceUnlock` slot, because the simulator has no biometric hardware. |

Screenshot names:

| Prefix | Launch | Shows |
|---|---|---|
| `a01`, `a02` | First launch, permissions reset | The welcome with no prompt on it, then the camera prompt after Not Now |
| `a101` to `a111` | Guest, far | The eleven faces in order |
| `a30`, `a31`, `a4-app-*` | Guest | Home Screen, top and scrolled, and each app a guest may open, empty |
| `b101` to `b111` | Recognized member, near, sample data | The eleven faces with detail |
| `b30`, `b31`, `b4-app-*`, `b45` | Recognized member | Home Screen and apps with content, an alarm added |
| `b50` to `b53` | Recognized member | Timer presets, the ring, the list, the capsule on a face |
| `b60` to `b64` | Recognized member | Recipe entry, cover, ingredients, two steps |
| `b70` | Recognized member | Profile switcher |
| `c10` to `c13` | Guest, near, fill layout | Fill layout faces and Home Screen, and the Home app with scenes locked |
| `c20` | Profile picked by hand | Home Screen with personal items greyed out |
| `c30` | Night hook | Night clock |
| `c40` to `c42` | Touch ID hook | Home Screen and switcher with the Touch ID affordance, then Messages opened by it |
| `p10` to `p13`, `p20` | iPhone | The four companion tabs, and the Hub tab with a summary |
| `d10` to `d14` | iPad mini, companion, 466 by 678 | Outer display: the four tabs, and the Hub tab with no hub |
| `d20` to `d23` | iPad mini, companion, 626 by 890 | Inner display upright: two columns with Beam, Apps, and People, and with no hub |
| `d30`, `d31` | iPad mini, companion, 890 by 626 | Inner display on its side: two columns |
| `d32`, `d33` | iPad mini, companion, 678 by 466 | Outer display on its side: tabs |
| `d40` | iPad mini, companion, full screen | An iPad set to Companion: two columns |
| `h10` to `h12` | iPad mini, hub, 626 by 890 | Inner display upright: face, Home Screen, Alarms |
| `h20` to `h23` | iPad mini, hub, 466 by 678 | Outer display: face, Home Screen, Alarms, profile switcher |
| `h30`, `h31`, `h32` | iPad mini, hub, 890 by 626 and 678 by 466 | Both displays on their side |
| `h40` to `h42` | iPad mini, hub, 890 by 626, fold hook | Folded like a book: the face on one side; status, timers, and widgets on the other |
| `h43` | iPad mini, hub, 626 by 890, fold hook | Folded across: the face above, the rest below |
| `h50` | iPad mini, hub, 626 by 890, fill layout | The second column below the canvas |

The `d` and `h` images show the whole iPad mini screen with the framed app in the middle.

`design/screenshots/before/` holds the walkthrough from before the visual pass.
