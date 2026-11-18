# HomePad animations

`Packages/HomePadAnimations` holds the Lottie animations the app plays and the SwiftUI view that
plays them. Every animation file is written by a script in this repository. Nothing was
downloaded.

## Catalog

All files use a 400 x 400 canvas at 60 fps with a transparent background. Strokes are white so
they sit on the black hub screen.

| Case | File | Purpose | Frames | Playback | Tintable parts |
|---|---|---|---|---|---|
| `.success` | `success.json` | A circle draws on, then a checkmark draws inside it and settles. | 90 | once | ring, checkmark |
| `.faceScan` | `face-scan.json` | Face enrollment ring: 60 radial ticks with a highlight that sweeps around. The center is empty for the camera preview. | 120 | loop | highlight ticks |
| `.beamIncoming` | `beam-incoming.json` | A page rises into the display, ripple rings spread behind it, and its text lines draw. | 150 | once | ripple rings, text lines |
| `.beamSending` | `beam-sending.json` | A page leaves the phone and follows an arc to the display, leaving a dotted trail. | 180 | loop | dots, text lines |
| `.presencePulse` | `presence-pulse.json` | Faint rings spread from a dot that breathes. | 180 | loop | all |
| `.timerDone` | `timer-done.json` | A bell swings and settles while motion arcs flash beside it. | 150 | loop | all |
| `.pairing` | `pairing.json` | A phone and a display move apart, come together, and a link glyph appears between them. | 180 | loop | link glyph |
| `.hello` | `hello.json` | First launch: six rainbow stripes sweep in, then a display on its stand draws around them in white. | 210 | once | none |
| `.listening` | `listening.json` | Five bars rise and fall like a waveform. | 120 | loop | all |
| `.locked` | `locked.json` | A padlock shackle drops shut and a keyhole appears. For personal content that is locked. | 90 | once | all |
| `.guest` | `guest.json` | A person glyph inside a ring of four arcs that breathes. For the guest experience. | 180 | loop | ring arcs |

A looping animation ends on the picture it starts on, and that picture is a useful still: the
linked devices for `.pairing`, the full dotted trail for `.beamSending`, the bell at rest for
`.timerDone`. Reduce Motion shows that last frame.

`HomePadAnimation.loops`, `.supportsTint`, `.frameCount`, and `.duration` carry the same facts in
code. A test compares them with the files.

## Using the view

```swift
import HomePadAnimations
import HomePadAnimationsCore

HomePadAnimationView(.listening)                               // loops
HomePadAnimationView(.success, loop: false)                    // plays once
HomePadAnimationView(authored: .hello)                         // follows HomePadAnimation.loops
HomePadAnimationView(.pairing, isPlaying: isSearching, tint: .accentColor)
HomePadAnimationView(.success, loop: false, tint: .green)
    .onFinished { dismiss() }
```

- The view scales to the space it gets and keeps a square shape. Give it a frame.
- `loop` defaults to true for every animation. Pass `loop: false`, or use `init(authored:)`, for
  the play-once animations.
- `onFinished` runs once when a play-once pass reaches its last frame. Looping playback never
  calls it. Setting `isPlaying` to false and back to true starts a new pass.
- Reduce Motion: the view shows the last frame and does not move. `onFinished` still runs, after
  the time the pass would have taken, so a flow that waits for it keeps its pacing.
- The view pauses on its current frame while it is offscreen, while the app is in the
  background, and while `isPlaying` is false. A loop starts again from its first frame.
- The view is hidden from accessibility. Put the label on the control or text beside it.

## Tinting

Every stroke and fill in the files is named after its role:

| Name | Role | Keypath constant |
|---|---|---|
| `Tint` | Takes the accent color. White in the file. | `HomePadAnimationKeypath.tintColor` (`**.Tint.Color`) |
| `Ink` | Neutral outline, such as the phone and the display. White in the file. | `HomePadAnimationKeypath.inkColor` (`**.Ink.Color`) |
| `Stripe` | Fixed color. Only the rainbow stripes in `hello.json`. | none |

`HomePadAnimationView(..., tint:)` sets a `ColorValueProvider` on the tint keypath. `.hello` has
no `Tint` parts, so a tint does nothing there. The ink keypath is there for a caller that needs
dark outlines on a light background and drives Lottie directly.

## Regenerating

The files come from `Packages/HomePadAnimations/Tools/generate_animations.py`, which needs only
the Python 3 standard library. Do not edit the JSON by hand.

```sh
cd Packages/HomePadAnimations
python3 Tools/generate_animations.py            # write Sources/HomePadAnimationsCore/Resources/*.json
python3 Tools/generate_animations.py --check    # exit 1 if a file on disk differs from the script
python3 Tools/generate_animations.py --list     # name, frames, loop or once, tint or fixed
```

The output is deterministic: the same script always writes the same bytes. The unit tests do not
run Python, so run `--check` before you commit a change to the script or to the files.

To look at the result, render preview sheets on the Mac. Each sheet shows six evenly spaced
frames on black:

```sh
HOMEPAD_ANIMATION_PREVIEW_DIR="$PWD/Packages/HomePadAnimations/Tools/preview" \
  Scripts/test-package.sh HomePadAnimations --filter PreviewFrameTests
```

The sheets under `Tools/preview/` are drawn by Lottie's main thread engine on the host. The app
uses the Core Animation engine on the device, which has not been watched on hardware yet.

## Adding an animation

1. Write a builder function in `generate_animations.py` and add it to `CATALOG`. Name accent
   strokes and fills with `tint(...)` or `tint_fill(...)` and outlines with `ink(...)`.
2. For a loop, give every animated property the same first and last value. `periodic(...)`
   builds keyframes for a cycle that crosses the loop point.
3. Run the script, then add the case to `HomePadAnimation` with its raw value equal to the file
   name, and fill in `loops`, `supportsTint`, and `frameCount`.
4. Update the expected lists in `HomePadAnimationTests` and add the row to the catalog above.
5. Render the preview sheet and look at it. Run `Scripts/test-package.sh HomePadAnimations` and
   `Scripts/build-package.sh HomePadAnimations`.

## Lottie features in use

The generator stays inside what the lottie-ios 4.6.1 Core Animation engine draws. A test loads
every file with the automatic engine option and fails if Lottie falls back to the main thread
engine.

Used:

- Shape layers only, each spanning the whole animation.
- Groups with one path item each: ellipse, rounded rectangle, or bezier path.
- Strokes with round or butt caps and round joins. Solid fills.
- Trim paths (start and end) on stroked shapes.
- Keyframes on layer position, scale, rotation, and opacity, on ellipse and rectangle size, on
  trim end, and on stroke and fill opacity. Easing uses cubic bezier handles inside 0...1.
- Static group transforms.

Not used: expressions, effects, masks, track mattes, merge paths, repeaters, gradients, dashes,
images, text, precompositions, time remapping, layer parenting, 3D, trim on fills, and animated
bezier paths.

## License

lottie-ios 4.6.1 (https://github.com/airbnb/lottie-ios) is licensed under Apache-2.0. It is the
one third-party dependency in the project. The app has to show the Lottie copyright and license
text with its acknowledgments. The animation files are original work produced by the generator
in this repository and carry no third-party license.
