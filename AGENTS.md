# HomePad: agent guide

iPadOS and iOS 26+ app. iPad is the hub, iPhone is the companion. Root: this directory.

## Invariants

1. iOS and iPadOS only, deployment target 26.0. No macOS, Catalyst, visionOS, tvOS, watchOS.
2. Every preference is a `SettingKey` with a `SettingDescriptor`, shown by `HomePad/Settings.bundle`.
   No in-app control changes a preference. The app never writes a preference.
3. `HomePad/Settings.bundle/*.plist` are generated. Never edit them by hand.
4. `HomePad.xcodeproj` is generated from `project.yml`. Never edit the project by hand.
5. Personal content shows on the hub only while `HouseholdSession.isPersonalContentUnlocked` is
   true and only for `activeProfile`. Only a face match with a live result unlocks it.
6. The hub listener is TLS-PSK only, runs only while the scene is active, and needs a paired
   device or an open invitation. No other listening socket exists. Do not add one without auth.
7. Secrets and face templates live in the Keychain, this device only. Never in defaults, files, logs.
8. Relayed message bodies stay in memory. Never persist or log them.
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
| `Packages/HomePadMessaging` | Projection templates and protocol, message relay, App Intents, notes |
| `Packages/HomePadKiosk` | Kiosk state machine, Single App Mode, passcode prompt |
| `Packages/HomePadAnimations` | Lottie wrapper, generated animations, `Tools/generate_animations.py` |
| `Packages/HomePadSettingsCatalog` | All descriptors, Settings bundle writer, `homepad-settings` tool |
| `docs/` | `UI`, `FACE_RECOGNITION`, `FACE_MODEL`, `BEAM`, `MESSAGING`, `KIOSK`, `ANIMATIONS` |

Each feature package has `<Name>Core` (pure logic, host-tested) and `<Name>` (iOS frameworks,
SwiftUI). Put decisions in Core. The manifest drops the iOS target when `HOMEPAD_HOST_TESTS` is set.

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
| Unit tests for one package (Mac host, with coverage) | `Scripts/test-package.sh <Package>` |
| Compile one package for an iOS device | `Scripts/build-package.sh <Package>` |
| Regenerate the Settings bundle | `Scripts/generate-settings.sh` |
| Check the Settings bundle is current | `Scripts/generate-settings.sh --check` |
| Regenerate the Xcode project | `xcodegen generate` |
| Build the app for the iPad simulator | `Scripts/build-app.sh` |
| Walk the hub in the simulator, save screenshots | `Scripts/ui-walkthrough.sh` |
| Tile the screenshots into one image | `Scripts/contact-sheet.py <out.jpg> "<glob>"` |
| Regenerate animations / check them | `python3 Packages/HomePadAnimations/Tools/generate_animations.py [--check]` |
| Verify the face model against its fixtures | `xcrun coremlcompiler compile HomePad/Models/FaceEmbedder.mlpackage <dir>` then `swift Scripts/verify-face-model.swift <dir>/FaceEmbedder.mlmodelc Scripts/face-model-fixtures` |

Builds are capped (`nice`, `-j 3` or `-jobs 4`). Run one at a time. Check free memory and disk
before booting a simulator: the runtime is 8 GB and a booted iPad needs several GB of RAM.

## Verify before finishing

1. `Scripts/test-package.sh` for every package you touched. Core targets hold 100% line coverage.
2. `Scripts/generate-settings.sh --check`
3. `Scripts/build-app.sh` exits 0.
4. `Scripts/ui-walkthrough.sh` passes, and the screenshots in `design/screenshots` look right.
5. `grep -rn "NWListener\|listen(" Packages HomePad Extensions` shows only `PeerLink.swift`.
