# Design specification from the user

This is the user's description of Apple HomeView's interface, given as the target for HomePad's
hub. It is kept as the user wrote it, lightly reformatted. Two instructions from the user override
it where they differ:

- The iPad is rectangular. The hub expands to fill the display. The 1:1 canvas below describes
  HomeView's hardware and gives the proportions, tokens, and visual language, not a fixed viewport.
- HomePad requires iOS and iPadOS 27 and requires Siri AI (Apple Intelligence) to be enabled.

What a third-party app cannot do (FaceTime calls, Siri's own wake word and overlay, Find My,
other apps' Live Activities, a real ambient light sensor reading, Secure Enclave face matching) is
listed in `docs/UI.md` with what HomePad does instead.

## Overview

Apple HomeView (running homeOS / HomeView Software 27.2) is an ambient, proximity-adaptive,
multi-user smart display built around a 1:1 square Liquid Retina viewport (1088 x 1088 px at 220
ppi, 544 x 544 pt logical canvas) with zero physical buttons. Unlike iPadOS, which optimizes for
single-user, arm's-length productivity, HomeView is engineered as a room-scale spatial surface that
dynamically morphs its visual density based on who is looking at it, how far away they stand, and
ambient room lighting.

## 1. Hardware canvas and core design tokens

- Viewport geometry: 1:1 square (544 x 544 pt logical, 1088 x 1088 px physical) inside a uniform
  black bezel with continuous superellipse corners (radius 60 pt, about 22% of canvas width).
- Input model: multi-touch, far-field voice, and computer-vision proximity and identity sensing
  through a top-bezel 12MP Center Stage camera. No hardware home, volume, or power buttons.
- Luminance: 500 nits down to 0.3 nits (bedside Night Mode), with True Tone.
- Material language (Liquid Glass): translucent frosted layers with subtle specular rim
  highlights, background refraction, and adaptive tinting over ambient wallpapers.

```json
{
  "canvas": {
    "logicalWidthPt": 544,
    "logicalHeightPt": 544,
    "physicalResolutionPx": "1088x1088",
    "dpi": 220,
    "aspectRatio": "1:1",
    "screenCornerRadiusPt": 60,
    "outerSafeMarginPt": 16,
    "gridGutterPt": 12
  },
  "materials": {
    "liquidGlassTile": {
      "background": "rgba(255, 255, 255, 0.14)",
      "backdropFilter": "blur(28px) saturate(160%)",
      "border": "1px solid rgba(255, 255, 255, 0.28)",
      "boxShadow": "inset 0 1px 1px rgba(255, 255, 255, 0.35), 0 8px 24px rgba(0, 0, 0, 0.25)",
      "borderRadiusPt": 28
    },
    "oledNightMode": {
      "canvasBackground": "#000000",
      "primaryTint": "#FF2D20",
      "secondaryTint": "rgba(255, 45, 32, 0.55)",
      "luminanceNits": 0.3
    }
  },
  "typography": {
    "fontFamilyPrimary": "-apple-system, 'SF Pro Display', 'SF Pro Rounded', sans-serif",
    "heroMetricFarField": { "sizePt": 96, "weight": 300, "tracking": "-2pt" },
    "heroMetricNearField": { "sizePt": 72, "weight": 400, "tracking": "-1.5pt" },
    "tileTitle": { "sizePt": 17, "weight": 600 },
    "tileSubtitle": { "sizePt": 14, "weight": 400, "opacity": 0.72 }
  }
}
```

## 2. Adaptive spatial and identity rules

Before rendering any screen state, the UI evaluates two variables: proximity and identity.

### Proximity

| Zone | Distance | Behavior |
|---|---|---|
| Far-field (ambient) | more than 2.5 m | Glanceable: oversized primary metrics (68, clock hands, big weather icon), high contrast. Secondary subtitles and micro-controls fade out (opacity 0). |
| Mid-field (approach) | 1.0 m to 2.5 m | Contextual: room labels, live camera thumbnails, and widget subtitles fade in (opacity 0.75). |
| Near-field (touch) | less than 1.0 m | Interactive: granular controls (dimmer tracks, thermostat steppers, scrollable app icons, text input) expand, with touch targets of at least 44 x 44 pt. |

### Identity and privacy

Up to 6 enrolled household members by on-device face recognition, plus a Guest / Shared state.

- **Guest (default shared room view):** public household faces (Home Modular, clocks, Weather,
  shared photo albums), shared music playback, and room smart-home controls. Personal
  notifications, Calendar, Messages, and Reminders are completely suppressed.
- **Recognized resident:** when a known user approaches, the system authenticates their profile
  (face match alongside their paired iPhone or iPad on the local network). A subtle top-edge pill
  briefly confirms identity (avatar and name), unlocking their personalized Home Screen, private
  Calendar and Messages widgets, and personal assistant context.

## 3. Screen states

### State 1: Ambient faces (idle and glanceable)

Faces are the default resting state. Switch by swiping horizontally, or long-press the background
to enter a watchOS-style Face Switcher carousel (with a bottom Customize pill button).

**1A. Home Modular (primary smart-home dashboard)**

- Grid: asymmetric 2-column x 3-row bento layout (16 pt outer padding, 12 pt gap) of Liquid Glass
  squircle cards (28 pt radius) over a user-selected wallpaper.
- Hero tile (top-left, 250 x 336 pt, rows 1 and 2): the primary control, typically Thermostat. A
  40 x 40 pt circular translucent icon badge at top-left, huge temperature numerals centered
  vertically, bold "Thermostat" label, muted room tag. Tapping opens a full-bleed circular thermal
  dial.
- Clock tile (top-right, 250 x 162 pt): circular analog dial (148 pt) inside a frosted glass disc
  with 60 radial minute ticks, white hour and minute hands, and a sweeping accent second hand.
- Live camera tile (middle-right, 250 x 162 pt): rounded live camera feed with a subtle top-right
  live dot. Tapping expands to a full-screen camera view.
- Bottom accessory dock (row 3, three equal 162 x 164 pt tiles): quick-toggle tiles (Fan,
  Door Lock, Lights). Each has a 36 pt circular SF Symbol badge at top-left and two-line stacked
  text at bottom-left. A tap toggles power or lock state (the glass tile becomes solid white with
  dark text when on). A long press opens a vertical slider popover.

**1B. Standard Modular (high-contrast grid)**

A symmetric 2 x 2 grid of 4 scaled-up widgets (250 x 250 pt each) with widget backgrounds stripped
away on pure black. Typical slots: Calendar (coral month header and a bold white day numeral), a
high-contrast analog clock, a sensor trend sparkline, and a Live Activity widget.

**1C. Home Camera**

1, 4 (2 x 2), or up to 9 (3 x 3) live camera streams in a tight 4 pt gutter matrix. Tapping a tile
zooms it to full screen with a top-left room badge, a bottom-center two-way microphone button (only
when the camera supports two-way audio), and event pills (Person, Package, Animal, Vehicle).

**1D. Expressive and timepiece faces**

- Analog and Digital: edge-to-edge clocks with serif, rounded, or stencil numerals and palettes.
- Fade: a sundial-inspired timepiece where peripheral hour numerals fade in and out as the
  sweeping hand passes them.
- Flow: a real-time generative fluid gradient mesh that ripples and shifts hue velocity in
  response to movement and proximity in the room.
- Photos and Memories: full-bleed albums with portrait depth segmentation, with time and date
  typography on a layer behind the subject's head and shoulders.
- Weather: a live sky simulation (clear, rain, cloud cover) with oversized current temperature,
  high and low, and a precipitation bar.
- Snoopy: animated Peanuts vignettes. (Not built: licensed artwork.)

### State 2: Night Mode (low-light bedside)

- Trigger: ambient light below the dark-room threshold.
- Display brightness ramps down to its minimum.
- Wallpapers, Liquid Glass blurs, and multi-color accents are stripped to pure #000000.
- All clock hands, numerals, and widgets render only in a monochrome red tint (#FF2D20).

### State 3: Personalized Home Screen and scrolling app grid

- Trigger: swipe up from the bottom edge while within reach (or automatically on recognition when
  configured).
- Widget zone (top or left): per recognized user. 1 or 2 interactive Liquid Glass widgets
  (calendar agenda, reminders checklist, music up next).
- App launcher zone: a 4-column grid of squircle app icons (76 x 76 pt, 17 pt corner radius, 12 pt
  white labels underneath).
- Vertical scroll: inertial spring physics, a subtle top and bottom edge mask blur, and a vertical
  page-indicator pill along the right edge (6 pt inset).
- App roster: Home, Music, Calendar, FaceTime, Messages, Safari, Photos, Timers, Alarms, Intercom,
  Find My, Weather, Podcasts, Settings, plus supported media apps from the paired iPhone. No App
  Store icon.
- Return to face: swipe down from the top, or press the bottom gesture bar.

### State 4: Full-screen app and smart-home control views

Tapping an app icon or expanding a widget transitions with a hero zoom into a full-screen view.

- **Home app and room controls**
  - Navigation: a top horizontal scrollable pill bar (All, Living Room, Kitchen, Bedroom, Cameras).
  - Thermostat expanded view: a centered 340 x 340 pt circular arc dial with a blue-to-amber
    thermal gradient track, a draggable thumb, a giant central target temperature, a smaller
    current temperature ("Inside 69"), and a Liquid Glass mode selector (Off, Heat, Cool, Auto) at
    the bottom.
  - Lighting or dimmer modal: a vertical pill slider (120 x 320 pt, 40 pt corner radius) that fills
    from bottom to top in warm amber (#FFD60A), with circular color-temperature swatches below.
- **Music and lyrics**: a blurred full-bleed album-artwork backdrop; a square album cover (180 x
  180 pt) with bold track title, artist, scrubber, and transport controls, or a full-screen synced
  lyrics view, with a bottom-right AirPlay multiroom pill.
- **Cooking and recipes**: a high-contrast step-by-step layout for messy hands: a large step badge
  ("Step 2 of 6"), 24 pt instruction text, highlighted ingredient quantities, and a persistent
  floating timer pill ("12:45 Pasta") in the top corner.

### State 5: FaceTime and Center Stage

- Incoming call banner: a floating Liquid Glass pill (512 x 88 pt, 44 pt radius) from the top safe
  area with the caller's circular photo (56 pt), bold name, "FaceTime Video" subtitle, a 56 pt red
  Decline button, and a 56 pt green Accept button.
- Active call: full-bleed remote video; a local self-view (116 x 148 pt, 24 pt radius) anchored in
  a corner and draggable to any corner, reframed by Center Stage; a bottom-center translucent
  control pill (320 x 68 pt, 34 pt radius) with four 48 pt circular buttons (Effects, Mute, Camera,
  End Call in #FF3B30) that fades after 4 seconds without touch and returns on a tap.

### State 6: System overlays

- **Control Center (swipe down from the top-right):** a heavy frosted glass scrim (40 pt blur) over
  the current view, with a 2-column grid of rounded modules: a vertical display brightness slider
  (with the Night Mode toggle), a vertical speaker volume slider, an Intercom push-to-talk tile, Do
  Not Disturb, accessibility shortcuts, and the user profile switcher.
- **Live Activities (top-edge pill):** anchored at the top center, 16 pt down, as a compact 260 x
  44 pt black or glass pill for active timers, deliveries, scores, or rides. Tapping expands it
  into a 512 x 220 pt interactive card without leaving the face.
- **Siri AI overlay (voice or top-edge trigger):** a continuous iridescent glowing edge light
  tracing the screen border. Spoken responses and visual answers appear in a bottom-anchored
  Liquid Glass floating card (512 pt wide, dynamic height) with conversational text, personal
  context snippets (calendar events, messages, playlists), and tappable follow-up chips.
