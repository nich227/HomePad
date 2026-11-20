# HomePad: agent guide

iPadOS and iOS 27+ app. iPad is the hub, iPhone is the companion. Root: this directory.

## Invariants

1. iOS and iPadOS only, deployment target 27.0. No macOS, Catalyst, visionOS, tvOS, watchOS.
   An API newer than iOS 27.0 goes behind `if #available` with the iOS 27.0 behavior as the fallback.
   Layout adapts by size class and container size. Never branch on a device model.
   Every `Package.swift` declares `platforms: [.iOS("27.0")]` and nothing else. Unit tests run on
   the iOS simulator through `Scripts/test-package.sh`, never on the Mac. No package has an
   executable target.
2. Every preference is a `SettingKey` with a `SettingDescriptor`, shown by `HomePad/Settings.bundle`.
   No in-app control changes a preference. The app never writes a preference.
3. `HomePad/Settings.bundle/*.plist` are generated. Never edit them by hand.
4. `HomePad.xcodeproj` is generated from `project.yml`. Never edit the project by hand.
5. Personal content shows on the hub only while `HouseholdSession.isPersonalContentUnlocked` is
   true and only for `activeProfile`. Only a face match with a live result unlocks it.
6. The hub listener is TLS-PSK only, runs only while the scene is active, and needs a paired
   device or an open invitation. No other listening socket exists. Do not add one without auth.
7. Secrets and face templates live in the Keychain, this device only. Never in defaults, files, logs.
8. Projected iPhone content and household notes stay in memory. Never persist or log them.
9. One capture session uses the front camera: the face package's. The Mirror shares it.
10. `HomePadIdentifiers` (Core) and `Config/Shared.xcconfig` must agree on bundle prefix and app group.
11. lottie-ios is the only third-party dependency. Animation JSON is generated, not downloaded.
12. Build output goes under `build/` (ignored by git and by the workspace file sync).

## File map

| Path | Holds |
|---|---|
| `project.yml` | Targets, Info.plist keys, entitlements, package list |
| `Config/Shared.xcconfig` | Bundle prefix, app group, team, deployment target, platforms |
| `Config/HomePadKiosk.mobileconfig` | Profile that permits Single App Mode for the bundle ID |
| `HomePad/HomePadApp.swift` | `@main`, `AppRootView`, `HomePadAppIntents` |
| `HomePad/AppModel.swift` | Builds hub or companion services, scene phase, extension settings mirror |
| `HomePad/HubSceneView.swift` | Hub root, slot wiring, banners, kiosk overlay, beam routing |
| `HomePad/CompanionSceneView.swift` | iPhone root and slots |
| `HomePad/SharedMirrorCamera.swift` | `CameraPreviewService` backed by the face camera |
| `HomePad/HomePadAppShortcuts.swift` | `AppShortcutsProvider`. Must stay in the app target |
| `HomePad/Models/FaceEmbedder.mlpackage` | SFace model. `NOTICE.md` beside it |
| `HomePad/Settings.bundle` | Generated Settings panes |
| `Extensions/BeamShare` | Share extension, links `HomePadBeam` |
| `Extensions/MessagesExtension` | iMessage extension, links `HomePadMessagingCore` only |
| `HomePadUITests` | Simulator walkthrough that saves screenshots |
| `Packages/HomePadCore` | Profiles, `HouseholdSession`, `HomePadSettings`, `PeerChannel`, identifiers |
| `Packages/HomePadUI` | Faces, Home Screen, native apps, `HubFeatureSlots`, companion shell |
| `Packages/HomePadFace` | Camera, Vision, Core ML embedder, enrollment, recognition, liveness |
| `Packages/HomePadBeam` | `PeerLink` (implements `PeerChannel`), pairing, beam, SharePlay, Handoff |
| `Packages/HomePadMessaging` | Projection templates and protocol (Calendar, Reminders, Now Playing), App Intents, household notes |
| `Packages/HomePadAssistant` | Apple Intelligence gate, the in-app Assistant (model, speech, overlay), hub actions as App Intents |
| `HomePad/HubAssistantBridge.swift` | Implements the Assistant's actions and context over the hub's services |
| `HomePad/HubRecipeEnhancer.swift` | Maps the Recipes reader's enhancer onto the Assistant's recipe formatter |
| `Packages/HomePadKiosk` | Kiosk state machine, Single App Mode, passcode prompt |
| `Packages/HomePadAnimations` | Lottie wrapper, generated animations, `Tools/generate_animations.py` |
| `Packages/HomePadSettingsCatalog` | All descriptors, Settings bundle writer, the test that writes `Settings.bundle` |
| `docs/` | `UI`, `FACE_RECOGNITION`, `FACE_MODEL`, `BEAM`, `MESSAGING`, `ASSISTANT`, `KIOSK`, `ANIMATIONS`, `DESIGN_SPEC` |

Each feature package has `<Name>Core` (pure logic, unit-tested, 100% line coverage) and `<Name>`
(iOS frameworks, SwiftUI, no unit tests). Put decisions in Core. Both targets are always in the
manifest. Tests are Swift Testing in `Tests/<Name>CoreTests` and run on the iOS simulator.

| Package | Test scheme | Coverage target |
|---|---|---|
| `HomePadCore` | `HomePadCore` | `HomePadCore` |
| `HomePadSettingsCatalog` | `HomePadSettingsCatalog` | `HomePadSettingsCatalog` |
| every other package | `<Name>-Package` | `<Name>Core` |

`Scripts/test-package.sh` picks the scheme. A test reads an environment variable `<NAME>` when the
caller sets `TEST_RUNNER_<NAME>`; a test in the simulator can read and write this Mac's files.

## When you change X, also change Y

| Change | Also do |
|---|---|
| Add, remove, or edit a `SettingDescriptor` | `Scripts/generate-settings.sh`, then `Scripts/test-package.sh HomePadSettingsCatalog` |
| Add a settings enum in a package | Append it in `SettingsCatalog.descriptors` |
| A setting an extension reads | Add its key to `SettingsCatalog.sharedWithExtensions` |
| Add a source directory, target, capability, Info.plist key | Edit `project.yml`, then `xcodegen generate` |
| Bundle prefix or app group | `Config/Shared.xcconfig`, `HomePadIdentifiers`, `Config/HomePadKiosk.mobileconfig` |
| Add an App Intent | Put it in `HomePadMessaging`; add phrases in `HomePad/HomePadAppShortcuts.swift` |
| Add a `HomePadAnimation` case | Add it to `Tools/generate_animations.py`, run it, run the package tests |
| Add a `HubApp` or slot | `HubFeatureSlots`, `AppCatalog` (UI Core), `HubSceneView.slots`, `CompanionSceneView.slots` |
| Replace the face model | `Scripts/convert-sface.py`, `Scripts/verify-face-model.swift`, `HomePad/Models/NOTICE.md`, `EmbedderModelProfile` |
| Change the app icon | `Scripts/make-icon.swift`, regenerate `AppIcon.png` and the iMessage icon set |
| Change a public API in a package | The app files in `HomePad/` that call it, and that package's doc in `docs/` |

## Commands

| Need | Command |
|---|---|
| Unit tests for one package (iOS simulator, with coverage) | `Scripts/test-package.sh <Package> ["simulator name"]` |
| One suite or test of a package (no coverage) | `Scripts/test-package.sh <Package> "iPhone 18 Pro" -only-testing:<TestTarget>/<Suite>` |
| Uncovered lines of one file after a test run | `xcrun xccov view --report --functions-for-file <File>.swift build/test-<Package>.xcresult` |
| Compile one package for an iOS device | `Scripts/build-package.sh <Package>` |
| Regenerate the Settings bundle | `Scripts/generate-settings.sh` |
| Check the Settings bundle is current | `Scripts/generate-settings.sh --check` |
| Regenerate the Xcode project | `xcodegen generate` |
| Build the app for the iPad simulator | `Scripts/build-app.sh` |
| Walk the hub in the simulator, save screenshots | `Scripts/ui-walkthrough.sh` |
| Walk the companion on iPhone | `Scripts/ui-walkthrough.sh "iPhone 18 Pro"` |
| Capture iPhone Duo sizes (no Duo simulator here) | `Scripts/ui-walkthrough.sh "iPad mini (A20 Pro)"` |
| Tile the screenshots into one image | `Scripts/contact-sheet.py <out.jpg> "<glob>"` |
| Regenerate animations / check them | `python3 Packages/HomePadAnimations/Tools/generate_animations.py [--check]` |
| Write animation preview sheets | `TEST_RUNNER_HOMEPAD_ANIMATION_PREVIEW_DIR="$PWD/Packages/HomePadAnimations/Tools/preview" Scripts/test-package.sh HomePadAnimations "iPhone 18 Pro" -only-testing:HomePadAnimationsCoreTests/PreviewFrameTests` |
| Verify the face model against its fixtures | `xcrun coremlcompiler compile HomePad/Models/FaceEmbedder.mlpackage <dir>` then `swift Scripts/verify-face-model.swift <dir>/FaceEmbedder.mlmodelc Scripts/face-model-fixtures` |

Builds are capped (`nice`, `-jobs 3` or `-jobs 4`). The build and test scripts take a lock
(`Scripts/lib/lock.zsh`, held in `build/.lock`), so a second one waits for the first to finish.
Never call `xcodebuild` for this project outside those scripts. Check free memory and disk
before booting a simulator: the runtime is 8 GB and a booted iPad needs several GB of RAM.

| Script | Simulator | Default device | Shuts it down |
|---|---|---|---|
| `Scripts/test-package.sh` | boots | iPhone 18 Pro | yes |
| `Scripts/generate-settings.sh` | boots (through `test-package.sh`) | iPhone 18 Pro | yes |
| `Scripts/ui-walkthrough.sh` | boots | iPad Pro 13-inch (M5) | yes |
| `Scripts/build-app.sh`, `Scripts/build-package.sh` | no | | |

`Scripts/test-package.sh` writes `build/DerivedData-<Package>`, `build/test-<Package>.xcresult`,
and `$TMPDIR/homepad-test-<Package>.log`. It exits non-zero when the build or a test fails.

## Verify before finishing

1. `Scripts/test-package.sh` for every package you touched. Core targets hold 100% line coverage.
   The script prints `coverage <Target>: <percent>` and each file below 100%.
2. `Scripts/generate-settings.sh --check`
3. `Scripts/build-app.sh` exits 0.
4. `Scripts/ui-walkthrough.sh` passes on iPad Pro, iPhone 18 Pro, and iPad mini for a UI change,
   and the screenshots in `design/screenshots` look right.
5. `grep -rn "NWListener\|listen(" Packages HomePad Extensions` shows only `PeerLink.swift`.
6. `grep -rn "macOS\|AppKit" --include="*.swift" Packages HomePad Extensions HomePadUITests` shows nothing.
