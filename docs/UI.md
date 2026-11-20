# HomePadUI: the hub shell and the companion shell

`Packages/HomePadUI` draws the HomeView-style experience on the iPad hub and the companion on
the iPhone. The hub fills whatever shape the display is: every face, the Home Screen, and every
app is laid out for the space it has. The target look is written down in `docs/DESIGN_SPEC.md`.
Both shells adapt to the two displays of a folding iPhone (see "Sizes and folding displays").
The package has two targets:

| Target | What it holds |
|---|---|
| `HomePadUICore` | Pure logic, unit-tested on the iOS simulator at 100% line coverage: the hub's state machine and gesture zones, the grids, the design tokens, Night Mode, clock math, time text, the timer state machine, alarm scheduling, layouts and their store, the app and widget catalog with visibility rules, the recipe parser and the recipe reader's session, Flow face math, the rules for sizes and folds, and `UISettings`. |
| `HomePadUI` | SwiftUI views and the services behind them (HomeKit, Music, camera, Core Location, WeatherKit, Photos, Vision). |

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
        projectedApps: { AnyView(ProjectedAppsView()) },
        people: { AnyView(PeopleView()) },
        recognitionIndicator: { AnyView(RecognitionChip()) },
        pairing: { AnyView(PairingView()) },
        deviceUnlock: HubDeviceUnlock(
            isOffered: { session.canConfirmWithDeviceBiometrics },
            unlock: { await deviceBiometrics.confirm() }
        ),
        assistant: HubAssistant(
            isAvailable: { assistant.isAvailable },
            overlay: { dismiss in AnyView(AssistantOverlay(onDismiss: dismiss)) }
        ),
        intercom: { AnyView(HouseholdNotesView()) },
        calendar: nil,
        liveItems: { intercom.liveItems }
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
- `facePosition` also leans the wallpaper behind glass tiles, for a slow parallax.

### Driving the hub from outside the shell

`HubNavigator` is the app's handle on the hub. Everything here is `@MainActor`.

```swift
public private(set) var state: HubNavigationState
public private(set) var isNightMode: Bool
public private(set) var enabledFaces: [FaceKind]
public private(set) var currentFace: FaceKind?
public internal(set) var isDoNotDisturbOn: Bool
public var screenTitle: String { get }

public func setNightMode(_ isOn: Bool)
@discardableResult public func showFace(_ kind: FaceKind) -> Bool
@discardableResult public func open(_ app: HubApp, context: AudienceContext) -> Bool
@discardableResult public func handle(_ event: HubEvent, context: AudienceContext) -> Bool
public func present(_ overlay: HubOverlay)
public func dismissOverlay()
public func showFaces()
public func showHomeScreen()
public func back()
public func presentBeam()
public func dismissBeam()
public func openRecipe(_ url: URL, context: AudienceContext)
```

- `isNightMode` is the hub's real night state, however it came about. `setNightMode` does what
  the control center's switch does: it holds until the next start or end hour of the night
  schedule, it is never stored, and asking for what the hub already shows changes nothing. The
  hub carries it out while it is on screen, and `isNightMode` follows then.
- `showFace` brings the faces to the front on that face and returns false, changing nothing,
  when the face is not turned on in Settings (or the hub has not appeared yet, when
  `enabledFaces` is still empty). An open assistant stays open over the face, so the assistant
  can answer and then close itself.
- `screenTitle` is the localized name of what is in front: a face's name, an app's name, "Home
  Screen", "Control Center", "Faces", "Assistant", "Thermostat", "Light", "Camera", or "Beam"
  during a takeover. It names a kind of screen and never what is on it.
- `FaceKind.displayName` and `HubApp.displayName` are public, localized `String`s.
- `isDoNotDisturbOn` is true while Do Not Disturb is on in the control center. The hub silences
  its own timer and alarm sounds and holds back `liveItems`; the app should hold its banners.

### Slots

`HubFeatureSlots` is a struct of closures. Each view slot has a placeholder.

| Slot | Where it appears on the hub | On the companion |
|---|---|---|
| `beam` | Beam app on the Home Screen, and the full-screen takeover | Beam section |
| `projectedApps` | iPhone Apps app. Personal: hidden for guests, greyed out until a face unlocks it | Apps section |
| `people` | People app, only while Setup Mode is on | People section, only while Setup Mode is on |
| `pairing` | Pairing app, only while Setup Mode is on | People section, only while Setup Mode is on |
| `recognitionIndicator` | Inside the status capsule at the top trailing corner, before the name and avatar | not shown |
| `intercom` (optional) | Intercom app, for members, and an Intercom module in the control center. Nil leaves both out | not shown |
| `calendar` (optional) | Calendar app. Personal. Nil leaves the icon out | not shown |
| `assistant` (optional) | A control in the status area and a module in the control center while `isAvailable()` is true; `overlay(dismiss)` is drawn over everything | not shown |
| `liveItems` | Extra `LivePillItem`s for the pill at the top of a face. Mark anything personal with `isPersonal` | not shown |

An optional app has no icon while its slot is nil (`VisibilityPolicy.isListed`), because an icon
that does nothing is worse than no icon.

On the companion a section is a tab in a compact width and the trailing column in a regular
width. The `beam`, `people`, and `pairing` slots are placed inside a `NavigationStack`, so a slot
view sets a title and does not bring its own stack. The `projectedApps` slot fills its section
and brings its own. The companion puts no custom view in a toolbar, because the system cannot
move a custom view into the bars it draws down the side of a folding iPhone.

Slot apps are drawn by `SlotScreen`: a title and a round close button above, a black
background, and the dark color scheme. The slot's text is stepped up through Dynamic Type
(`SlotTextScale`) so ordinary text styles read from across a room; the view is not scaled. A
slot view should lay out for a rectangle of any size, use text styles and not fixed point sizes,
and put an empty state in the middle of the space and not inside a `List` row.

### The assistant

```swift
public struct HubAssistant {
    public var isAvailable: @MainActor () -> Bool
    public var overlay: @MainActor (_ dismiss: @escaping @MainActor () -> Void) -> AnyView
    public init(isAvailable:overlay:)
}
```

While `isAvailable()` is true the hub shows a sparkles button in the status area
(`hub.assistant`) and an Assistant module in the control center (`control.assistant`), and a
pull down from the middle of the top edge opens it too. The overlay is drawn above everything,
including a beam takeover, over the whole pane, and the hub passes it the closure that closes
it. A swipe up from the bottom edge and the idle timer also close it. Night Mode's tint is
not applied to it: the app passes it `HubNavigator.isNightMode` and it draws itself red. The
hub never names the assistant: its labels say "Assistant".

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

- A round button beside the avatar in the status at the top trailing corner (`hub.deviceUnlock`).
- Each locked personal app icon: the lock badge becomes a Touch ID badge and the icon accepts a tap.
- Each locked personal widget: the tile shows the symbol and "Unlock with Touch ID".
- A round button in the control center's profile module (`switcher.deviceUnlock`).

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
someone would look for settings there is one way out to the system Settings app: the gear in
the control center, the Customize pill under the face picker, the Accessibility module, the
note shown when nobody is set up, the empty states that need a permission or a value, and the
Settings icon on the Home Screen.

Night Mode's switch and Do Not Disturb in the control center are not preferences. Both are held
in memory, end by themselves, and are gone after a relaunch.

Settings added or changed for the rectangular hub:

| Name | Title | Pane | Control | Default | Options |
|---|---|---|---|---|---|
| `ui.display.canvas` | Canvas | Display | Choice | `fill` (was `square`) | Fill the Screen, Square (like HomeView) |
| `ui.display.idleReturn` | Return to Face After | Display | Choice | `120` | 30 Seconds, 1 Minute, 2 Minutes, 5 Minutes, Never (`0`) |
| `ui.weather.location` | Location | Weather | Choice | `current` | Current Location, Custom |
| `ui.face.memories.enabled` | Memories | Faces | Toggle | on | |

Face options are household-wide, because a Settings bundle is static. What is per person is
state, kept in the `LayoutStore`: the last face they rested on and the order of their Home Screen
icons and widgets.

Setup Mode (`GeneralSettings.setupMode`) gates the `people` and `pairing` slots. With Setup Mode
off and nobody enrolled, the Home Screen shows a short note that points to Settings.

## The canvas and its layout rules

`CanvasLayout` says where the hub draws. With `ui.display.canvas` at **Fill the Screen**, the
default, the canvas is the whole space the app has (full screen, Split View, Stage Manager).
With **Square** it is the largest centered square on black with HomeView's rounded corners, and
everything below still applies inside it. There is no side column and nothing scrolls sideways,
with one exception: the room bar of the Home app when a home has more rooms than fit.

`HubMetrics` carries the canvas size. Sizes come from the design tokens (`DesignTokens` in Core),
which are given in points on a 544 point square and scaled by the canvas's shorter side:

| Token | On 544 pt | Token | On 544 pt |
|---|---|---|---|
| Outer margin | 16 | Tile title | 17 semibold |
| Gutter | 12 | Tile subtitle | 14 at 72% opacity |
| Tile radius | 28 | Hero number | 96 far, 72 mid and near |
| Screen radius (square canvas) | 60 | Icon badge | 36 |
| App icon | 76, radius 17 | Minimum touch target | 44, and never under 44 real points |
| Live pill | 260 by 44 | Live pill card | 512 wide |

Grids are chosen in Core from the container's size, never from a device:

| What | Rule | iPad landscape | iPad portrait | Square | Narrow (outer display) |
|---|---|---|---|---|---|
| Tile faces (`TileGrid(width:height:)`) | 2 to 4 columns and rows, at most 12 cells, the squarest cells, no cell under 120 pt unless nothing larger fits | 4 by 3 | 3 by 4 | 3 by 3 | 2 by 4 |
| Home Modular (`HomeModularLayout`) | Hero thermostat 2 by 2, clock beside it, small tiles fill the rest in reading order; tiles that do not fit are left out | hero + clock + 7 | hero + clock + 7 | hero + clock + 4 | hero + clock + 3 |
| Modular (`ModularLayout`) | Three columns when the aspect is 1.2 or wider, three rows when it is that much taller | 3 by 2, six widgets | 2 by 3, six widgets | 2 by 2, four widgets | 2 by 3 |
| Home Screen icons (`HomeScreenGrid.columns`) | Four columns, and more when the width allows, to eight | 5 (13-inch) | 4 | 4 | 4 |
| Home Screen widgets (`HomeScreenGrid.widgetCount`) | One row of two to six | 4 | 3 | 3 | 2 or 3 |
| Home Camera (`CameraGrid`) | 1, 2 by 1, 2 by 2, 3 by 2, or 3 by 3, with a 4 pt gutter | same | same | same | same |
| Control center | Glass modules on a grid four columns wide in landscape and two in portrait | 4 | 2 | 2 | 2 |
| Grids inside apps (`HubMetrics.columns`) | The count for a square, times the aspect on a wide screen | Timers 4, Photos 4 | 3 | 3 | 3 |

Other rules by orientation: the Flow face puts its four digits in one row when wide and two rows
otherwise; the Calendar face puts the large date beside the month when wide and above it when
tall; Music and the Home app put their two halves side by side when wide and stacked otherwise;
Analog and Fade keep round hands and move the numerals toward the edges of whatever shape the
screen is, and start below the pill and the status so those never cover the twelve.

### Chrome on the canvas

Three things float over a face and the Home Screen, inside the canvas:

- **The live pill**, top center (`hub.pill`): see "Overlays".
- **The status**, top trailing (`StatusCluster`): the `recognitionIndicator` slot, the name on
  approach where the screen is wide, and the avatar, in one glass capsule. A tap opens the
  control center (`hub.profile`). Beside it, while they apply, a Touch ID button and the
  assistant button. The pill never grows under it.
- **The bar**, bottom center (`HomeBar`): a tap goes to the Home Screen from a face or an app and
  back to the face from the Home Screen (`hub.showHomeScreen`, `hub.showFace`). It is the
  pointer and assistive-technology route for the swipe up from the bottom edge.

Faces made of tiles keep `HubMetrics.topBar` clear at the top and `bottomBar` at the bottom.
Full-bleed faces draw under the chrome. The top inset grows to clear the safe area and, on iOS
27.1 and later, anything `reservedRegions(kind: .occlusion)` reports, such as a camera.

## Liquid Glass and motion

Glass is the system's, not a hand-made blur. `hubGlass(in:tint:interactive:)` is the one place
it is applied:

| API | Used for | Available from |
|---|---|---|
| `glassEffect(_:in:)`, `Glass.regular`, `.tint`, `.interactive` | Every tile, widget, pill, capsule, and round button | iOS 26.0 |
| `GlassEffectContainer` | Tile boards, the control center, the pill, room and mode bars, so neighboring glass blends | iOS 26.0 |
| `glassEffectID(_:in:)` | The live pill morphing into its card and back | iOS 26.0 |
| `MeshGradient` | Wallpapers, the Flow field | iOS 18.0 |
| `scrollTransition` | Faces sliding in the pager and in the face picker | iOS 17.0 |
| `contentTransition(.numericText())` | Every changing number: time, temperature, countdowns, brightness | iOS 17.0 |
| `contentTransition(.symbolEffect(.replace))`, `symbolEffect(.pulse)`, `.bounce` | Play and pause, toggles, the running timer glyph, a ringing alarm | iOS 17.0 |
| `onScrollGeometryChange`, `onGeometryChange` | The page indicator, pull down to close, icon positions | iOS 18.0 |
| `defersSystemGestures(on:)` | The hub's own edge swipes take the first swipe | iOS 16.0 |
| `ArrangementView`, `reservedRegions(kind:)` | A folded display | iOS 27.1, behind `#available` with a fallback |

The minimum is iOS 27.0, so only the last row needs an availability check.

With Reduce Transparency on, glass becomes a solid fill with a hairline edge and the blurred
scrims become plain black. In Night Mode there is no material at all, only an outline.

Wallpapers (`HubWallpaper`) are drawn in code in the active profile's color: a mesh gradient,
two soft dark shapes, and a lighter sweep. They lean a little with the viewer's position when
`facePosition` is supplied, near shapes more than far ones.

`HubMotion` holds the three animations the shell uses: a spring for moving between surfaces and
opening overlays, a snappy one for controls, and a gentle one for density, night, and wallpaper.

- Face to Home Screen: the face scales up a little and blurs while the Home Screen rises.
- Opening an app: the app grows out of the icon that was tapped (an anchored scale from the
  icon's measured center) and shrinks back into it. `matchedTransitionSource` with
  `navigationTransition(.zoom)` needs a `NavigationStack` or a full-screen cover, which cannot
  sit under the hub's overlays, so the zoom is done by hand.
- Overlays scale and fade in over a blurred scrim. The pill morphs through `glassEffectID`.
- Density changes cross-fade labels and controls in place.

Reduce Motion replaces every one of these with a short fade, stops the clock sweep, the Flow
drift, the wallpaper's lean, the Memories drift, and falling rain.

Lottie animations from `HomePadAnimations` still mark single moments: `hello` on first run,
`timerDone` when a timer finishes, `presencePulse` around the avatar while someone is in view,
`beamIncoming` when a page takes over the screen, and `listening`, `pairing`, and `faceScan` in
empty states.

## Sizes and folding displays

Nothing here checks for a device model. Layout follows the size class, the size of the
container, and what the system reports about the display. That covers an iPhone, an iPad in any
window size, and iPhone Duo, which has a compact-width outer display (about 466 by 678 points)
and a regular-width inner display (about 626 by 890 points) that folds across its middle. The
rules are in `HomePadUICore/AdaptiveLayout.swift` and `TileGrid.swift`.

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

The hub is two panes: the canvas, and a chrome pane that is empty while the display is flat.

| iOS | Container | Display flat | Display partly folded |
|---|---|---|---|
| 27.1 and later | `ArrangementView` with the `.overlay` style. The chrome is the primary view and the canvas the secondary | The canvas fills the display and carries its own chrome | The system gives each pane one side of the fold: the canvas leading or on top, the chrome trailing or below |
| 27.0 | `ZStack` | The same | Not applicable: no folding device runs this version |

Each pane measures itself against the whole container (`HubPanePolicy.placement`). A pane with
less than three quarters of the area has been given a side of its own. Then:

- The canvas pane fills its side, and leaves the status out of the canvas.
- The chrome pane fills its side (`ChromePanelLayout`): the status across the top
  (`BezelStatusView`), the timer strip under it, then widgets in the grid that suits the space
  (`SidePanelGrid`).

With the display flat the hub lays out for the display's size like any other: the inner display
upright gets the portrait rules above and the outer display the narrow ones. Round buttons
never get smaller than 44 points.

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

## Proximity

`Proximity` has three zones and `FaceDensity` follows it. The shell animates between them.

| Zone | Density | Shows |
|---|---|---|
| `.far` | `.glanceable` | The large numbers only. Subtitles, room names, and small controls are faded out. The hero number is at its largest. |
| `.mid` | `.contextual` | Labels, room names, subtitles, thumbnails, and the name in the status fade in. |
| `.near` | `.detailed` | Controls appear, each at least 44 points: the thermostat's chevrons, Play and Pause, the weather details. |

`ui.display.adaptiveDetail` off keeps the detailed layout at any distance. Tile faces keep the
same grid at every distance and change what is inside the tiles, so nothing jumps.

## Faces

Swipe left or right to change faces, or use the arrow keys. Touch and hold a face for the face
picker.

| Face | Far | Mid | Near | Reference |
|---|---|---|---|---|
| Modular | Large widgets with no backgrounds on black: date, analog clock, weather, now playing, home, timers; numbers only | Captions | The Play or Pause pill | `homeview-reference.jpg`, `newsroom-collection-of-faces.jpg` |
| Photos | Photo with four very tall translucent digits, behind the person in the photo when one is found | The date | same | `product-faces-endframe.jpg` |
| Memories | The chosen photos one after another, each drifting slowly and fading into the next, with the time | The day the photo was added | same | written specification |
| Weather | A drawn sky that follows the conditions, the time, a very large temperature, high and low | Place name and the precipitation bar | A row of four details | `newsroom-collection-of-faces.jpg` |
| Home Modular | Glass bento over the wallpaper: hero thermostat, clock, camera, scenes, and quick toggles, with titles only | Room names and the camera's name | The thermostat's chevrons | `product-dashboard.jpg`, `newsroom-lifestyle-living-room.jpg` |
| Calendar | Month, time, very large day number, weekday | The month grid with today circled, the date beside or above it | same | `newsroom-collection-of-faces.jpg` |
| Flow | Liquid digits on a pink and blue field | The date | same | `newsroom-collection-of-faces.jpg` |
| Analog | Numerals and hands | The second hand and "WED 1" | same | `newsroom-collection-of-faces.jpg` |
| Fade | Numerals fade in as the minute hand sweeps past them and out behind it | Over a wider arc | same | `newsroom-collection-of-faces.jpg` |
| Digital | Date and a larger time | AM or PM and two small spots: weather and now playing | same | none |
| Home Camera | One, four, or nine camera pictures edge to edge with a 4 pt gutter | Room badges | same | none |
| Rainbow | Six stripes and the time | The date | same | our own |

On Home Modular and in the Home app, a tap on a tile switches it and the tile turns solid white
with dark text while it is on; a held press on a light opens the dimmer; a tap on the
thermostat opens the dial; a tap on a camera opens it full screen.

Photo depth uses Vision's `GeneratePersonInstanceMaskRequest` (iOS 18) on the chosen photo, on
the device. When it finds a person, the digits are drawn behind them. With no person the photo
keeps the plain layout with the digits on top.

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
- **Home Modular**: glass tiles over a wallpaper with one two by two thermostat tile (large
  number, down and up chevrons, name and room), a clock on a frosted disc beside it, and small
  tiles with a round badge, bold name, and lighter room name. A tile that is on is solid white
  with dark text.
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
- **Music** (`guide-music-player.png`): a dark blur of the artwork behind, round glass buttons
  in the top corners, large artwork with rounded corners, the title and artist, a scrubber with
  elapsed and remaining times, and previous, pause, next.
- **Recipe cover** (`guide-recipe.png`, `newsroom-cooking.jpg`): full-bleed photo, round glass
  close button, time at top right, bold title, "source, time, servings" line, and two wide glass
  capsules, Ingredients and Start Cooking.
- **Home Screen** (`guide-home-screen-apps.png`, `product-multiuser-endframe.jpg`,
  `newsroom-user-recognition.jpg`): the blurred face behind, the uppercase greeting and name, the
  round avatar at top right, a row of widgets, and columns of large rounded icons with labels.
- **Home app** (`newsroom-home-touch.jpg`): rounded tiles in a grid. The grid follows the
  screenshot. The colors follow the written specification: glass over the wallpaper, and a
  tile turns solid white when its accessory is on.
- **First run** (`guide-hello.png`): a warm red, pink, and yellow shape on cream behind a hello
  animation, with two wide capsules, Not Now and Add People. The capsules are solid, because
  glass on cream loses a white label.

### What was approximated

- **Typefaces.** Only system fonts are used. The tall digits use SF at compressed width stretched
  vertically; HomeView's digit shapes are narrower and have a glass edge. The Flow face draws
  blurred, thresholded SF Rounded digits and loose drops, which gives liquid shapes but not
  HomeView's exact glyphs.
- **Wallpapers and photos.** No Apple artwork is copied. Wallpapers are drawn shapes in the
  active profile's color; the Weather face draws its sky, sun, clouds, stars, rain, and snow;
  the Photos and Memories faces show the wallpaper until photos are chosen.
- **App icons.** Icons are SF Symbols on a rounded square in one of the six rainbow colors or
  grey, 76 points with a 17 point radius on the reference square.
- **Glass.** The recipe in the specification (14% white fill, strong blur with raised
  saturation, a 28% white hairline, an inner top highlight, a soft shadow) is what the system
  material is asked to look like; the pixels are the system's.
- **Digital and Home Camera.** No screenshot showed these, so they follow the written
  descriptions.
- **Fade.** The review screenshot could not be fetched. The gray dial and blue second hand come
  from the written description; the layout comes from the pink Fade face in Apple's image.
- **Recipe steps, ingredient list, timer controls, the control center, alarms, mirror.** No
  screenshot showed these screens. They follow the written specification and reuse the visual
  pieces that are shown.
- **Empty states.** Every native app uses one layout (`HubEmptyState`): a large symbol, a title,
  one line of explanation, and at most one action.

### What is left out, and why

- **Snoopy.** Licensed artwork.
- **Messages, FaceTime, Find My, and Podcasts.** A third-party app cannot provide them, and an
  icon that does nothing is worse than no icon, so they are not on the Home Screen.
- **Lyrics** in Music, and the queue. No public API.
- **Camera event pills.** HomeKit does not give an app a camera's events. The microphone button
  shows only for a camera that reports a speaker and a microphone it lets an app control.
- **Push-to-talk Intercom.** The Intercom control opens the household note composer.
- **Safari.** The browser is the Beam app, and its icon says Beam, because it shows pages sent
  from an iPhone and is not a general browser.

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


## The state machine

`HubNavigationState` (Core) is where the hub is: a surface (`.faces`, `.homeScreen`,
`.app(HubApp)`), at most one overlay (`HubOverlay`), and the beam takeover above both. Every
gesture and tap becomes a `HubEvent` and goes through `handle(_:context:)`, so audience rules
are applied in one place. `HubGesture.event(...)` turns a drag into an event from where it
started.

| From | Event | To |
|---|---|---|
| Face, nothing over it | Swipe left or right, arrow keys | Next or previous face |
| Face, nothing over it | Touch and hold (`.longPressCanvas`) | Face picker over the face |
| Face picker | Tap a face (`.chooseFace`) | That face, picker closed |
| Face picker | Customize | The Settings app |
| Face or app | Swipe up that starts in the bottom 12% (`.swipeUpFromBottomEdge`), or the bar | Home Screen |
| Anything with an overlay or a takeover | Swipe up from the bottom edge | The takeover closes first, then the overlay |
| Home Screen | Swipe down that starts in the top 16% (`.swipeDown`), pull down past the top of the grid, the bar, or Escape | Face |
| Anywhere | Swipe down that starts in the top 16% and the trailing 35% (`.swipeDownFromTopTrailing`), or a tap on the status | Control center over what is showing |
| Anywhere, assistant available | Pull down from the top edge within 15% of the center (`.openAssistant`), or its button | Assistant over everything |
| Home Screen | Tap an icon or widget (`.tapApp`) | The app, if the person may open it |
| Face or Home app | Tap the thermostat, hold a light, tap a camera (`.tapInlineControl`) | The dial, the dimmer, or the camera, over what is showing |
| Any overlay | Tap outside, its close button (`.dismissOverlay`) | Overlay closed |
| App | Close button, Escape (`back()`) | Home Screen |
| Home Screen, or an app with nothing playing | No touch for the idle period (`.idle`) | Face. Overlays close too |
| App while music plays; Recipes; Mirror | No touch for the idle period | Stays. A recipe is read, and a mirror watched, without touching |
| Anything | Who may see what changes (`audienceChanged`) | An app the person may not see closes to the Home Screen |
| A beam takeover, the Beam app, or a personal app | The audience signs out: `HouseholdSession.audienceGeneration` changes (`audienceSignedOut`) | The takeover closes, and the app gives way to the face. A member the camera lost for a moment is still signed in, and nothing closes for them |
| Anything | A page arrives (`presentTakeover`) | The beam slot covers the screen until closed |
| Anything | `showFace(_:enabled:)` from outside | Faces in front on that face; an open assistant stays |

A vertical drag that starts away from the top and bottom edges is not an event, so scrolling
inside an app or the Home Screen is never taken for a swipe. A drag that starts where it opens
the control center or the assistant (`HubGesture.startsOverlay`) does only that: the Home
Screen under it does not also take it as a pull down to the face. The idle period is
`ui.display.idleReturn`. Recognition does not move the hub by itself: there is no "open the
Home Screen when recognized" setting.

A new kind of overlay is a new case in `HubOverlay` and a line in the root view's switch.

## Overlays

- **Control center** (`ControlCenterView`): glass modules over a heavy blur. Brightness is a
  tall track that fills from the bottom, with the Night Mode switch above it. Volume is the
  system's `MPVolumeView`, turned upright. Do Not Disturb, Accessibility (opens Settings),
  Intercom and Assistant when their slots are filled, now playing with play and next, running
  timers, and the profile module: each member and Guest, the Touch ID button when offered, and
  the gear. Choosing a profile by hand never unlocks personal content.
- **Do Not Disturb** (`QuietTime`): until it is switched off or the night schedule's end hour
  next comes round. Finished timers and due alarms still show and make no sound, `liveItems`
  are held back, and `HubNavigator.isDoNotDisturbOn` tells the app.
- **Face picker** (`FacePickerView`): the enabled faces as live previews, one page each, with
  the face's name above and the Customize pill below.
- **Live pill** (`LivePillView`, `LivePill` in Core): compact at the top center, it grows in
  place into a card on a tap and back on another. It carries the hub's own live things, at most
  four: a brief confirmation with the member's avatar and name when the camera recognizes them,
  running timers, what is playing with its transport, and whatever `liveItems` reports. A guest,
  and a member whose personal content is locked, never see an item marked personal. A household
  note opens Intercom while that slot is filled and nothing otherwise.
- **Thermostat dial** (`ThermostatDialView`, `ThermostatDial` in Core): a three-quarter arc from
  blue to amber with a thumb to drag, the target in large numerals, "Inside" with the current
  temperature, and Off, Heat, Cool, Auto when the thermostat reports a mode.
- **Dimmer** (`DimmerView`, `DimmerMath`): a tall pill that fills from the bottom in amber, with
  white-point swatches under it when the light reports a color temperature.
- **Camera** (`CameraZoomView`): one camera live over the whole canvas with its room badge.
- **Assistant**: see "The assistant".

Timer and alarm alerts and the first-run welcome cover the canvas as before.

## Home Screen

Swipe up from the bottom edge of a face. Over the blurred face it shows the greeting and the
active profile's name (or Guest), one row of the person's widgets, and a grid of app icons that
scrolls up and down with the system's scroll physics. The grid fades out toward the top and
bottom edges, and a small pill on the trailing edge follows the scroll position. Drag an icon or
widget onto another to reorder; the order is saved per profile.

The face behind is a backdrop, not a picture: it is scaled up, has its contrast halved and its
saturation raised, and is blurred by `token(104)` under a 30% black overlay, so a white tile or a
dark camera picture on the face becomes an even wash of the face's color instead of a patch under
the icons. In Night Mode the backdrop is black.

The roster, in order: Home, Music, Calendar (when supplied), Beam, Photos, Timers, Alarms,
Intercom (when supplied), Weather, Recipes, Mirror, Clock, iPhone Apps, People and Pairing
(Setup Mode), and Settings. There is no Messages app.

A layout saved by an earlier version may name an app or widget that no longer exists, such as
Messages. Those entries are dropped when the file is read and the rest of the layout is kept.

Who sees what is decided by `VisibilityPolicy`:

| Access | Apps | Widgets | Guest | Profile picked by hand | Face recognized |
|---|---|---|---|---|---|
| guest | Clock, Timers, Home, Music, Mirror, Recipes, Weather, Beam, Settings | Clock, Calendar, Weather, Timers, Now Playing, Home, Thermostat, Camera, Photo | shown | shown | shown |
| member | Alarms, Photos, Intercom | Next Alarm | hidden | shown | shown |
| personal | iPhone Apps, Calendar | none | hidden | greyed out with a lock badge, cannot open. While Touch ID is offered, a tap asks for it | shown |
| setup | People, Pairing | none | only in Setup Mode | only in Setup Mode | only in Setup Mode |

When the person in front of the hub changes, an open app they may not see closes at once.

## Permission prompts

The hub asks for a permission when the person first reaches the thing that needs it, and never
on the welcome.

| Prompt | Appears |
|---|---|
| Camera | After the welcome is dismissed, or at launch when no welcome is due. The app starts face recognition from `onWelcomeFinished`. |
| HomeKit | The first time a face or widget that shows the home is in front, or the Home app opens. |
| Apple Music | The first time a now playing tile is on the face in front or scrolls into view, or the Music app opens. |
| Location | The first time weather is on the face in front, a weather widget scrolls into view, or the Weather app opens, and only with the Current Location setting. |
| Photos | Only with the Shared Album source, the first time the Photos or Memories face is in front. The photo picker needs no permission. |

Views start a service with the `startsOnFirstUse` modifier, which waits for `\.hubMayPrompt`.
That value is false while the welcome is up. In the face pager and the face picker it is true
only for the face in front, because neighboring faces are built ahead of time.

## Weather and location

`ui.weather.location` chooses where the weather is for. `WeatherPlace.resolve` (Core) turns the
setting, the permission, and the position into a place or a reason there is none.

1. **Current Location** (default). The first time weather is shown, `WeatherCenter.begin()` asks
   `SystemLocationProvider` for when-in-use permission (`CLLocationManager`, kilometer accuracy)
   and one position.
2. The position is named with `MKReverseGeocodingRequest` (`CLGeocoder` is deprecated from iOS
   26), and the city becomes the place name.
3. `WeatherKitWeatherProvider` asks WeatherKit for the current conditions, today's high and low,
   sunset, and today's chance of precipitation, every 30 minutes.
4. **Custom** uses the city and coordinates entered in Settings and never asks for location.

Every face, widget, and the Weather app say plainly why there is no weather
(`WeatherProblem`, `WeatherMessage`):

| State | Says | Offers Settings |
|---|---|---|
| Not asked yet | Weather Uses Your Location | no |
| Denied, or the usage description is missing | Location Is Off | yes |
| Allowed, no position yet | Finding This Place | no |
| Custom with no coordinates | Enter a Place | yes |
| The weather service did not answer | Weather Is Unavailable | no; it tries again |

## Apps

| App | Notes |
|---|---|
| Clock | Analog and digital time, date, next alarm. |
| Timers | Any number of named timers from a grid of presets. `TimerEngine` is the state machine; `TimerCenter` runs it, saves it, and rings. A started timer opens full screen. Running timers show in the live pill. A finished timer covers the canvas until stopped. |
| Alarms | One-time or daily alarms, set with large up and down buttons. Alarms ring while the app is in front. |
| Home | A bar of rooms across the top; the room's thermostat as a large tile; cameras, scenes, and accessories as glass tiles over the wallpaper. Tap to switch, hold a light for the dimmer, tap the thermostat for the dial, tap a camera for a live view. A guest can lock a door but not unlock one. Scenes: see below. |
| Music | A blurred backdrop of the artwork, the cover, title and artist, a scrubber to drag (`MusicService.seek`), transport, and the system's AirPlay route picker. Through `MPMusicPlayerController.systemMusicPlayer`. |
| Mirror | Front camera, full view or zoomed. |
| Recipes | Paste or beam a link. `RecipeParser` reads schema.org Recipe JSON-LD. The reader shows a cover, an ingredient checklist, and one step at a time. See "The recipe reader". |
| Weather | The Weather face with every detail. See "Weather and location". |
| Photos | The system photo picker. Chosen photos are copied into the app's storage. |
| Calendar, Intercom | Supplied through their slots. |

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


Services sit behind protocols (`HomeService`, `MusicService`, `CameraPreviewService`,
`WeatherProviding`, `LocationProviding`, `RecipePageLoading`, `RecipeEnhancing`) and `HubEnvironment.preview()`
supplies stand-ins, so every view previews without hardware.

## The recipe reader

The cooking screen follows the specification's layout for messy hands: a large numbered badge
with "Step 2 of 6", the instruction at 24 points on the reference square with its amounts
picked out in the accent color (`RecipeQuantities`), a timer button for any duration the step
mentions, and the running timer as a glass pill floating in the top corner.

| Distance | Shows |
|---|---|
| Far | The badge, the step's short title, and the instruction at 32 points |
| Mid | The section name and the ingredients the step uses, as glass chips |
| Near | Stop, previous and next, the timer button, and the "Tidied on this iPad" note |

### Tidying a recipe with a model

The reader has a hook for something that rewrites a recipe so it reads well in a kitchen. The
package does not depend on any model: the app supplies an enhancer, and without one recipes
show as their pages give them.

```swift
// HomePadUICore
public protocol RecipeEnhancing: Sendable {
    @MainActor func enhance(recipe: Recipe?, pageText: String, title: String) async -> Recipe?
}

public struct RecipeStep {
    public init(id: Int, title: String? = nil, text: String, timer: TimeInterval? = nil,
                ingredients: [String] = [], sourceStepID: Int? = nil)
}
public struct RecipeSection {
    public init(name: String? = nil, steps: [RecipeStep])
}
public struct Recipe {
    public init(name: String, summary: String? = nil, author: String? = nil, imageURL: URL? = nil,
                yield: String? = nil, prepTime: TimeInterval? = nil, cookTime: TimeInterval? = nil,
                totalTime: TimeInterval? = nil, ingredients: [String] = [],
                sections: [RecipeSection], isTidied: Bool = false)
}

// HomePadUI
public init(loader: any RecipePageLoading = URLSessionRecipePageLoader(),
            enhancer: (any RecipeEnhancing)? = nil)   // RecipeLibrary
```

- `recipe` is what the page's structured data gave, or nil when it had none. `pageText` is the
  page's readable text (`HTMLText.readable`: scripts, styles, and markup removed), cut off at
  `RecipeEnhancement.maximumPageTextLength` (12,000 characters). `title` is the page's title.
- The enhancer returns a `Recipe` or nil. `RecipeEnhancement.accepted` (Core) is what the reader
  takes from it: a name and at least one step with text. Steps are numbered again from one,
  `isTidied` is set, a step with no timer gets one from a duration in its text, each step keeps
  at most eight ingredient lines, and anything left out (picture, author, yield, times, the
  ingredient list) is filled in from the page's recipe.
- `RecipeStep.sourceStepID` is optional: the `id` of the step of the page's recipe that a
  rewritten step came from. With it the reader keeps the cook's exact place when it swaps;
  without it the reader goes to the same share of the way through.

What the reader does (`RecipeSession` in Core, `RecipeLibrary` in the view layer):

1. The page's own recipe shows at once. The reader never waits for the enhancer.
2. When the enhancer answers, the tidied recipe takes its place with a slow cross-fade. The
   step in front and the checked ingredients are carried over (`RecipePlace`): checks keep
   their positions when the two lists are the same length and otherwise follow the same words.
3. When the page has no structured recipe, the reader shows "Getting this recipe ready" while
   the enhancer reads the page's text. A nil answer, or no enhancer, gives the usual "No recipe
   was found on that page."
4. A tidied step shows its short title above the instruction and the ingredients it uses as
   chips. A quiet line says "Tidied on this iPad" with a button that switches to the page's own
   words and back, keeping the place. It is on the cooking screen and the ingredient list.
5. Opening another recipe, closing the recipe, or leaving the Recipes app cancels a request
   that is still under way. A recipe that was already on screen stays as the page gave it. An
   answer that arrives late for a visit that has ended is ignored.

The page's text is held only by the request to the enhancer and is gone when the request ends.
Nothing about a recipe is stored.

`SampleRecipeEnhancer` is a stand-in with no model, for previews and UI tests. It splits each
step into one action per step, names it with its first words, and lists the ingredients the
step mentions. `HubEnvironment.preview()` and `HOMEPAD_UITEST_SAMPLE` use it.

## Night Mode

Everything on the hub turns one color, red `#FF2D20`, on pure black, and the screen dims.

**When.** `NightModePolicy.appearance` (Core) decides: an override from the control center's
switch or `HubNavigator.setNightMode` while it is in force; otherwise the schedule from
Settings, and, with "Follow Room Light" on, the `ambientLight` hint (a dark room starts it
outside the window and a lit room cancels it inside). An override (`NightOverride`) lasts until
the schedule's next start or end hour, or twelve hours when the schedule has no hours, and is
gone after a relaunch.

**How.** It is decided in one place, at the root of the hub, which sets `\.hubIsNight` and puts
everything the hub draws and every view it hosts through one filter (`hubNightFilter`):
`grayscale(1)`, a little added contrast, and `colorMultiply` with the red. The assistant's
overlay is the one exception. The filter shows a view by its brightness, so something already
red comes out at about a third of its brightness. An assistant from another package is
therefore left out of the filter and has to draw itself red, from `HubNavigator.isNightMode`. That alone would
leave light backgrounds as red fields, so the same modifier sets `\.hubIsNight`, and the views
that draw a background read it and draw black: wallpapers, the weather sky, the Flow field, the
Calendar's paper, the Rainbow's stripes, colored clock dials, the Music backdrop, the scrims.
`hubGlass` draws a thin outline with no material, and app icons become outlines.

**Brightness.** On entering, `ScreenController` lowers the screen to the night level (never
raises it) and remembers what it was; on leaving, and whenever the app leaves the foreground,
it puts that back. The control center's brightness slider can raise it during the night.

**What it does not reach.** Anything the system draws outside the app's view tree: permission
alerts, the system volume overlay, the photo picker, the AirPlay route sheet, the keyboard, and
the Settings app. A view in a slot that paints a light background of its own becomes a red
field, not black, unless it reads the night state; `HubNavigator.isNightMode` is there for
that. Photos and camera pictures are shown in red monochrome, not hidden.

## What a third-party iPad app cannot do

Each line was checked against the iOS 27.2 SDK in Xcode 27.2.

| HomeView behavior | Status | Checked |
|---|---|---|
| Always-on, locked to one app | Not possible from inside the app. The device must be put in Guided Access, or be supervised for Single App Mode. | The only API is `UIAccessibilityRequestGuidedAccessSession`, which succeeds only on a supervised device that allows it. The kiosk package handles this. |
| Showing other apps' widgets | Not possible. Widgets here are the app's own views. | WidgetKit's interface has no type for hosting a widget from another process. |
| The system assistant on screen | Not possible. An app can only offer its actions through App Intents. The hub hosts the in-app Assistant from `HomePadAssistant` in its `assistant` slot instead (see `docs/ASSISTANT.md`). | `AppIntents.framework` is the only surface in the SDK; there is no API to present the system assistant. |
| Find My | Not possible. | The SDK has no Find My framework. |
| Ambient light sensor | Not available. The shell takes a hint from the app instead. | `UIScreen` and `UIDevice` expose no ambient light reading; `SRAmbientLightSample` is in SensorKit, which is limited to approved research studies. |
| Knowing how far away someone is | The shell does not measure it. `HouseholdSession.proximity` is driven by the face package. | n/a |
| Controlling other apps' audio | Only the Music app's player is reachable. | `MPMusicPlayerController.systemMusicPlayer` controls Music; there is no public API for another app's now playing session. |
| Messages, phone calls, and FaceTime calls | Not shown. HomePad does not show messages or take calls. | No public API reads Messages or takes over a phone or FaceTime call. |
| Podcasts | Not built. | No public API reaches the Podcasts app's library or player. |
| Other apps' Live Activities | Not possible. The pill carries the hub's own live things. | ActivityKit lets an app start and read only its own activities. |
| Lyrics | Not built. | MediaPlayer and MusicKit expose no lyrics for the playing item. |
| Camera event pills (person, package, motion) | Not built. | HomeKit gives an app a camera's stream and snapshots, not its recorded events. |
| Device volume | Only through the system's own slider, `MPVolumeView`. | No public API sets the output volume. |
| Doorbell takeover | Not built. | Out of scope for this package. |
| Alarms and timers that ring while the app is not in front | Not built. AlarmKit is in the SDK and could do it; it needs its own authorization and UI. | `AlarmKit.framework` exists; this package does not use it. |

## Info.plist keys and entitlements

| Key or entitlement | Needed for | Required |
|---|---|---|
| `NSHomeKitUsageDescription` and the HomeKit capability (`com.apple.developer.homekit`) | Home app, Home Modular, Home Camera | For home features. |
| `NSCameraUsageDescription` | Mirror | For Mirror. |
| `NSAppleMusicUsageDescription` | Music now playing | For Music. |
| `NSPhotoLibraryUsageDescription` | Photos face with the Shared Album source | Only for that source. The photo picker needs no key. |
| `NSLocationWhenInUseUsageDescription` | Weather for where the hub is | For the Current Location setting. Without the key the weather says location is off. |
| WeatherKit capability (`com.apple.developer.weatherkit`) | Weather | Optional. Without it weather shows as unavailable. |
| `com.apple.developer.avfoundation.multitasking-camera-access` | Mirror in Split View or Stage Manager | Optional. The session enables multitasking camera access when the device supports it. |

Each service checks that its usage description is in Info.plist before it asks for access, and
reports "not available" when the key is missing, so a missing key does not end the app.

No background modes. No network listener. Recipe pages are fetched over HTTPS with an ephemeral
session; plain HTTP pages are blocked by App Transport Security unless the app adds an exception.
State is stored under `Application Support/HomePad/UI` (layouts, timers, alarms, chosen photos);
none of it is a secret, and nothing is logged.


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
| `Scripts/ui-walkthrough.sh` (iPad Pro 13-inch) | `HubWalkthroughTests`: the hub in landscape |
| `TEST_RUNNER_HOMEPAD_ORIENTATION=portrait Scripts/ui-walkthrough.sh` | The same walk upright. Its screenshots start with `pt-` |
| `Scripts/ui-walkthrough.sh "iPhone 18 Pro"` | `CompanionWalkthroughTests`: the companion's tabs |
| `Scripts/ui-walkthrough.sh "iPad mini (A20 Pro)"` | `DuoWalkthroughTests`: the companion and the hub framed to the sizes of iPhone Duo's displays |

Controls are found by accessibility identifier. A container must not carry an identifier,
because it replaces the identifiers of the controls inside it.

The tests put the app in a known state through launch environment variables. `HubTestHooks`
(Core) parses the hub's in one place. Every hook is off unless its variable is set, debug builds
alone read them, and none is a preference.

| Variable | Effect |
|---|---|
| `HOMEPAD_UITEST_EPHEMERAL=1` | Layouts, timers, alarms, and photos stay in memory. |
| `HOMEPAD_UITEST_SAMPLE=1` | A sample household, home, music, weather, recipe page, and recipe enhancer stand in for the real services. Implies ephemeral. On the iPhone, a sample hub summary. |
| `HOMEPAD_UITEST_AUDIENCE=guest\|manual\|recognized` | Who is in front of the hub: nobody known, the first profile picked by hand, or the first profile recognized by face. |
| `HOMEPAD_UITEST_PROXIMITY=far\|mid\|near` | How close they are. |
| `HOMEPAD_UITEST_CANVAS=square\|fill` | The canvas for this launch, whatever Settings says. |
| `HOMEPAD_UITEST_NIGHT=1` | Night Mode, whatever the schedule says. The control center's switch still turns it off. |
| `HOMEPAD_UITEST_SOLID_GLASS=1` | Glass drawn as solid fills, as Reduce Transparency does. A test cannot turn that setting on. |
| `HOMEPAD_UITEST_SLOW_MOTION=8` | The shell's animations this many times slower, so a transition can be caught part way. |
| `HOMEPAD_UITEST_ASSISTANT=1` | A stand-in assistant when the `assistant` slot is empty, to exercise its controls and host. |
| `HOMEPAD_UITEST_SKIP_AI_GATE=1`, `HOMEPAD_UITEST_SCRIPTED_ASSISTANT=1` | Read by the app target and the Assistant package, set on every launch: no Apple Intelligence gate, and an assistant that answers from a script. |
| `HOMEPAD_UITEST_SKIP_WELCOME=1` | No first-run welcome. |
| `HOMEPAD_UITEST_ROLE=hub\|companion` | The role for this launch, whatever the device and Settings say. |
| `HOMEPAD_UITEST_VIEWPORT=626x890` | The whole app framed to this size in points, centered on black, with the size classes a display of that size reports. |
| `HOMEPAD_UITEST_FOLD=1` | Hub only. The two panes in halves with a gap between them, as if the display were partly folded. |
| `HOMEPAD_UITEST_DEVICE_UNLOCK=1` | A camera match without a liveness proof is waiting and Touch ID is offered. A tap on the affordance confirms it. |

Screenshot names (with `pt-` in front for the upright walk):

| Prefix | Launch | Shows |
|---|---|---|
| `a01`, `a02` | First launch, permissions reset | The welcome with no prompt on it, then the first prompt after Not Now |
| `a101` to `a112` | Guest, far, real services | The twelve faces in order |
| `a30`, `a31`, `a4-app-*` | Guest | Home Screen, top and scrolled, and each app a guest may open, empty |
| `b00` | Recognized member | The "recognized" confirmation in the pill |
| `b101` to `b112` | Recognized member, near, sample data | The twelve faces with controls |
| `b20`, `b201` | | The face picker, and after a swipe |
| `b21` to `b26` | | Home Modular: a light switched off, the dimmer, the dimmer set low, the thermostat dial, the dial dragged with Cool chosen, a camera full screen |
| `b30`, `b31`, `b4-app-*`, `b45` to `b47` | | Home Screen, apps with content, an alarm added, the Home app on one room, the dial from the Home app |
| `b50` to `b54` | | Timer presets, the ring, the list, the pill on a face, the pill expanded |
| `b60` to `b66` | | Recipe entry, the cover as the page gave it and then tidied, ingredients, a tidied step, a step with its ingredient chips and the timer pill, the page's own words, and tidied again |
| `b70`, `b71` | | Control center, and with Do Not Disturb on |
| `b80`, `b81` | | The assistant from the status area and from the control center |
| `c101` to `c112` | Recognized member, mid | The twelve faces with labels and no controls |
| `c20` to `c23` | Recognized member, far, sample data | Modular, Weather, Home Modular, Calendar across the room |
| `c30`, `c31` | Mid, then far | A tidied recipe step on approach and from across the room |
| `n101` to `n112`, `n20` to `n72` | Night hook | Every face, the face picker, Home Screen, five apps, the dial, a tidied recipe step, the assistant, the control center, then day again after the switch |
| `e10` to `e13`, `e10-control-center`, `e11-control-center-*` | Guest, near | A face, Home Modular with scenes locked, Home Screen, the Home app, the control center |
| `e20` | Profile picked by hand | Home Screen with personal items greyed out |
| `e40`, `e42` | Touch ID hook | Home Screen with the Touch ID affordance, then iPhone Apps opened by it |
| `e50`, `e51` | Square canvas | Home Modular and Home Screen in the square |
| `e60` to `e62` | Solid glass | Home Modular, control center, Home Screen |
| `f1` to `f6` | Slow motion | Frames through face to Home Screen, an app opening from its icon and closing into it, the control center opening, night coming on, and the assistant after a pull from the top center |
| `p10` to `p13`, `p20` | iPhone | The four companion tabs, and the Hub tab with a summary |
| `d10` to `d40` | iPad mini, companion | The companion at the outer and inner display sizes |
| `h10` to `h52` | iPad mini, hub | The hub at the inner and outer display sizes, upright and on its side, the control center, Night Mode, the square canvas, Home Modular and its dial, and the folded panes |

The `d` and `h` images show the whole iPad mini screen with the framed app in the middle.

`design/screenshots/before/` holds the walkthrough from before the first visual pass, and
`design/screenshots/before-redesign/` the one from before the hub filled the screen.
