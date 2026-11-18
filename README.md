# HomePad

HomePad turns an iPad into a shared home screen modeled on Apple HomeView. The iPad is the **hub**.
Each household member's iPhone runs the same app as a **companion**.

iPhone and iPad only, iOS and iPadOS 27 or later. Bundle ID `com.kevster.HomePad`.

## What it does

| Feature | How |
|---|---|
| Faces and a personal Home Screen | Eleven faces drawn on a square canvas like HomeView's screen, with apps and widgets per household member |
| Face recognition for any number of people | Vision finds and aligns the face, a bundled Core ML model (SFace, Apache-2.0) turns it into a vector, TrueDepth depth rejects photos |
| Beam a page from iPhone to iPad | A paired, encrypted local link, the share sheet, SharePlay, or Handoff |
| iPhone content on the hub | The iPhone projects Messages, Calendar, Reminders, and Now Playing as templates, the way CarPlay apps reach HomeView |
| Messages | A Shortcuts automation relays incoming messages, an iMessage extension sends pages, replies open the system compose sheet |
| Kiosk lock | The iPad stays on HomePad until someone enters the iPad passcode |
| Settings | Every preference is in the system Settings app |
| iPhone Duo | Tabs on the outer display, two columns on the inner display, and a hub layout that splits at the fold |

## Open and run

```sh
xcodegen generate          # writes HomePad.xcodeproj from project.yml
open HomePad.xcodeproj
```

Pick the `HomePad` scheme and an iPad or iPhone. Signing uses team `8ZUR795GTN`
(`Config/Shared.xcconfig`). The app needs the App Groups, HomeKit, and Group Activities
capabilities on that team.

## First run on the iPad

1. Open HomePad and choose Add People. Add each household member and enroll a face.
2. Open Pairing, then scan the code with HomePad on each iPhone (Beam tab).
3. On each iPhone, follow Set Up Message Relay to create the Shortcuts automation.
4. In Settings > Apps > HomePad, turn Setup Mode off.
5. For the kiosk lock, follow `docs/KIOSK.md`.

## What the platform does not allow

- **Reading Messages.** No app can read the inbox. The hub shows only what the automation
  relayed while HomePad was running on the iPhone.
- **Sending without a tap.** Every reply goes through the system compose sheet.
- **Face ID.** Recognition here is personalization. It does not run in the Secure Enclave, and
  only an iPad with a TrueDepth camera can unlock personal content from a face match.
- **Blocking the Home gesture.** An app can lock the iPad to itself only on a supervised iPad
  with the profile in `Config/`. Any other iPad needs Guided Access.
- **Hold the iPhone near the display.** No third-party trigger exists for this.
- **Touch ID.** It cannot tell household members apart. On an iPad without Face ID the camera
  picks the person and a fingerprint confirms that someone enrolled on the iPad is present.

## Where things are

| Path | Holds |
|---|---|
| `HomePad/` | The app target: wiring, scenes, assets, the model, the Settings bundle |
| `Extensions/` | The share extension and the iMessage extension |
| `Packages/` | One Swift package per feature, each with a unit-tested Core target |
| `Scripts/` | Build, test, Settings bundle, icon, and screenshot scripts |
| `Config/` | Shared build settings and the kiosk profile |
| `docs/` | One document per feature |
| `design/` | HomeView reference images and screenshots from the simulator |

## Checks

```sh
Scripts/test-package.sh HomePadFace      # unit tests for one package, on the iPhone simulator
Scripts/build-app.sh                     # build for the iPad simulator
Scripts/ui-walkthrough.sh                # launch, walk the hub, save screenshots
Scripts/generate-settings.sh --check     # Settings bundle matches the code
Scripts/generate-settings.sh             # rewrite the Settings bundle from the code
```

Everything builds for iOS and iPadOS only, and the unit tests run on the iOS simulator. The test
script starts the simulator (iPhone 18 Pro unless you name another as the second argument), prints
the test summary and the line coverage of the package's Core target, and shuts the simulator down.
A run takes about a minute and a half. Run one script at a time, because each simulator needs a
few gigabytes of memory.

## Licenses

- lottie-ios, Apache-2.0.
- SFace face model from the OpenCV Model Zoo, Apache-2.0. See `HomePad/Models/NOTICE.md`.
