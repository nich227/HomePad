# HomePadUI: the hub shell and the companion shell

`Packages/HomePadUI` draws the HomeView-style experience on the iPad hub and a small tab layout
on the iPhone companion. It has two targets:

| Target | What it holds |
|---|---|
| `HomePadUICore` | Pure logic, tested on the Mac host: clock math, time text, the timer state machine, alarm scheduling, layouts and their store, the app and widget catalog with visibility rules, night mode, the recipe parser, Flow face math, the canvas layout, and `UISettings`. |
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
        pairing: { AnyView(PairingView()) }
    ),
    environment: environment,
    navigator: navigator,
    facePosition: { faceTracker.normalizedPosition },
    ambientLight: { faceTracker.ambientLight },
    hubSummary: summaryReceiver.summary,
    onHubSummaryChange: { summary in Task { await broadcaster.publish(summary) } }
)
```

- Call `settings.register(UISettings.descriptors + GeneralSettings.descriptors + ...)` at launch.
- `HubEnvironment.live()` and `HubNavigator()` must be created once and kept, not built in `body`.
- When a page arrives from a companion, call `navigator.presentBeam()`. The beam slot then covers
  the whole screen, after a short arrival animation, until it is closed.
- When a beamed page is a recipe, call `navigator.openRecipe(url, context:)` to open it in the
  recipe reader.
- `HubSummaryBroadcaster` and `HubSummaryReceiver` carry "what the hub is showing" over any
  `PeerChannel` on the channel named `HubStatusSummary.channel`.

### Slots

`HubFeatureSlots` is a struct of `@MainActor () -> AnyView` closures. Each has a placeholder.

| Slot | Where it appears on the hub | On the companion |
|---|---|---|
| `beam` | Beam app on the Home Screen, and the full-screen takeover | Beam tab |
| `messages` | Messages app. Personal: hidden for guests, greyed out until a face unlocks it | not shown |
| `projectedApps` | iPhone Apps app. Personal, same rule as Messages | Apps tab |
| `people` | People app, only while Setup Mode is on | People tab, only while Setup Mode is on |
| `pairing` | Pairing app, only while Setup Mode is on | People tab, only while Setup Mode is on |
| `recognitionIndicator` | Next to the profile avatar on faces and on the Home Screen | Hub tab toolbar |

Slot views are drawn inside the square canvas with a close button above them, so they should lay
out for a square of any size and not assume the full screen.

## Settings

The app has no settings screens. Every preference is read through `HomePadSettings` from keys
declared in `UISettings` (`HomePadUICore/UISettings.swift`), and the app never writes one. Where
someone would look for settings (the profile switcher, the note shown when nobody is set up, and
the empty states that need a permission or a value) there is one "Open Settings" button that
opens the system Settings app. The Settings icon on the Home Screen does the same.

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
  column shows the timers, now playing, weather, and home widgets as the same glass tiles.

## Faces

Swipe left or right to change faces, or use the arrow keys. Swipe up, press the up arrow, or tap
the chevron for the Home Screen. Each face has two densities and animates between them:
`Proximity.far` shows less, larger; `.near` shows more. `ui.display.adaptiveDetail` turns this
off, which keeps the detailed layout.

| Face | Far | Near | Reference |
|---|---|---|---|
| Modular | Date and analog clock, large | Adds now playing and weather, four widgets | `homeview-reference.jpg`, `newsroom-collection-of-faces.jpg` |
| Photos | Photo with four very tall translucent digits | Adds the date | `product-faces-endframe.jpg`, `newsroom-collection-of-faces.jpg` |
| Weather | Condition, time, very large temperature | Adds high and low and a row of four details | `newsroom-collection-of-faces.jpg` |
| Home Modular | Thermostat, clock, four tiles without subtitles | Adds room names | `product-dashboard.jpg`, `newsroom-lifestyle-living-room.jpg` |
| Calendar | Month, time, very large day number, weekday | The month grid with today circled | `newsroom-collection-of-faces.jpg` |
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
  days outside the month, today in a navy circle, and the very large red day number behind.
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
- **Home app** (`newsroom-home-touch.jpg`): a light three-column grid of rounded tiles, lilac when
  on and grey when off, with a tile-less clock in the first cell.
- **First run** (`guide-hello.png`): a warm red and orange shape on cream behind a hello
  animation.

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
- **Recipe steps, ingredient list, timer controls, the profile switcher, alarms, mirror.** No
  screenshot showed these screens. They reuse the visual pieces that are shown: round glass
  buttons, wide glass capsules, the rounded-square tiles, and the orange timer accent.
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
another to reorder; the order is saved per profile. Pull down past the top, tap the chevron, or
press Escape to go back to the face.

Who sees what is decided by `VisibilityPolicy`:

| Access | Apps | Widgets | Guest | Profile picked by hand | Face recognized |
|---|---|---|---|---|---|
| guest | Clock, Timers, Home, Music, Mirror, Recipes, Weather, Beam, Settings | Clock, Calendar, Weather, Timers, Now Playing, Home, Thermostat, Camera, Photo | shown | shown | shown |
| member | Alarms, Photos | Next Alarm | hidden | shown | shown |
| personal | Messages, iPhone Apps | Messages | hidden | greyed out, cannot open | shown |
| setup | People, Pairing | none | only in Setup Mode | only in Setup Mode | only in Setup Mode |

When the person in front of the hub changes, an open app they may not see closes at once
(`HubNavigationState.audienceChanged`). Tapping the avatar opens the manual switcher, which calls
`HouseholdSession.switchManually` and so never unlocks personal content.

## Apps

| App | Notes |
|---|---|
| Clock | Analog and digital time, date, next alarm. |
| Timers | Any number of named timers from presets. `TimerEngine` is the state machine; `TimerCenter` runs it, saves it, and rings. Running timers show as a glass capsule on every face. A finished timer covers the canvas until stopped. |
| Alarms | One-time or daily alarms. They ring while the app is in front. |
| Home | Scenes, accessories on and off, brightness from the tile's context menu, thermostat target, and cameras through `HMCameraView` (snapshots in tiles, a live stream when opened). A guest can lock a door but not unlock one (`HomeControlPolicy`). |
| Music | Now playing and transport through `MPMusicPlayerController.systemMusicPlayer`. |
| Mirror | Front camera, full view or zoomed. |
| Recipes | Paste or beam a link. `RecipeParser` reads schema.org Recipe JSON-LD from the page's HTML; the reader shows a cover, an ingredient checklist, and one step at a time with a timer button for any duration the step mentions. |
| Weather | WeatherKit behind `WeatherProviding`. Off until a city and coordinates are entered in Settings. |
| Photos | The system photo picker. Chosen photos are copied into the app's storage. |

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
when a timer finishes, `presencePulse` around the profile chip while someone is in view,
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
