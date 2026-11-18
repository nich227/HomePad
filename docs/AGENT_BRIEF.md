# HomePad: brief for agents building feature packages

HomePad is an iPadOS and iOS app that recreates Apple HomeView features on an iPad. The iPad is the
shared **hub**. Each household member's iPhone runs the same app as a **companion**.

Project root: `/Volumes/workplace/HomePad/src/HomePad`

## Invariants

1. iOS and iPadOS only, deployment target 27.0. No macOS, Catalyst, visionOS, tvOS, or watchOS code paths.
2. Xcode 27.2, Swift 6.4, Swift 6 language mode (strict concurrency). `swift-tools-version: 6.2`.
3. You own exactly the directories named in your task. Do not edit anything else. Other agents are
   working in sibling directories at the same time. `Packages/HomePadCore` is read-only for you.
   If you need something added to Core, say so in your final report instead of editing it.
4. Do not create an `.xcodeproj`, run `xcodegen`, run `git`, install tools, or download models,
   fonts, or other binaries. No third-party dependencies. Apple frameworks only.
5. No network listener without authentication. No secrets, keys, or face data in `UserDefaults`,
   files, or logs. Secrets and biometric templates go in the Keychain with
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
6. Never log message bodies, URLs with query strings, face embeddings, or pairing secrets.
7. This machine is shared and already loaded. Build and test only through the two scripts below.
   Never run `xcodebuild` with default parallelism, never run two builds at once, and never boot
   a simulator yourself. The test script boots one and shuts it down.
8. No package declares or targets macOS. `platforms` is `[.iOS("27.0")]`, there is no executable
   target, and unit tests run on the iOS simulator. Do not use SwiftPM's command-line build, test,
   or run commands: they build for the Mac.

## Package layout (every feature package)

```
Packages/<Name>/
  Package.swift
  Sources/<Name>Core/      pure logic: Foundation, CryptoKit, Accelerate, Observation only
  Sources/<Name>/          iOS frameworks, SwiftUI views, services
  Tests/<Name>CoreTests/   Swift Testing, runs on the iOS simulator
```

Unit tests run on the iOS simulator and cover `<Name>Core` only. Code that needs a camera, a
paired device, an entitlement, or a person cannot be unit-tested there. So put every decision,
state machine, codec, and policy in `<Name>Core` and keep `<Name>` a thin shell around system
frameworks. The `<Name>` target is verified by compiling it for a device.

Use this manifest shape. Both targets are always present, and the test target depends on Core only:

```swift
// swift-tools-version: 6.2
import PackageDescription

let core = Target.Dependency.product(name: "HomePadCore", package: "HomePadCore")

let package = Package(
    name: "<Name>",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "<Name>Core", targets: ["<Name>Core"]),
        .library(name: "<Name>", targets: ["<Name>"]),
    ],
    dependencies: [.package(path: "../HomePadCore")],
    targets: [
        .target(name: "<Name>Core", dependencies: [core]),
        .target(name: "<Name>", dependencies: ["<Name>Core", core]),
        .testTarget(name: "<Name>CoreTests", dependencies: ["<Name>Core"]),
    ]
)
```

## Commands

| Need | Command (from the project root) |
|---|---|
| Unit tests on the iOS simulator, with coverage | `Scripts/test-package.sh <Name>` |
| One suite, no coverage | `Scripts/test-package.sh <Name> "iPhone 18 Pro" -only-testing:<Name>CoreTests/<Suite>` |
| Compile the package for an iOS device | `Scripts/build-package.sh <Name>` |
| Coverage of each target | `xcrun xccov view --report --only-targets build/test-<Name>.xcresult` |
| Coverage of each function in a file | `xcrun xccov view --report --functions-for-file <File>.swift build/test-<Name>.xcresult` |
| iOS SDK path, to check an API exists | `xcrun --sdk iphoneos --show-sdk-path` |

Both scripts are capped (`-jobs 3`, `nice`) and write their full output to a log under `$TMPDIR`.
`Scripts/test-package.sh` boots the "iPhone 18 Pro" simulator, prints the Swift Testing summary,
any failures, and the line coverage of `<Name>Core`, then shuts the simulator down. It finds the
scheme itself: a package with several library products has a `<Name>-Package` scheme that holds
the tests. A test run takes about a minute and a half, most of it the simulator starting.

To pass a value to a test, set `TEST_RUNNER_<NAME>` before the script. xcodebuild hands it to the
test process as `<NAME>`. A test in the simulator can read and write files on the Mac, so `#filePath`
and absolute paths work.

`Scripts/build-package.sh` builds the scheme named after the package. If the plain scheme is
missing, tell me in your report and build with `-scheme <Name>-Package` using the same flags as
the script.

When you are not sure an API exists in this SDK, check the `.swiftinterface` or header under the
SDK path before using it. Do not guess. iOS 27.0 APIs are fine to use, and newer ones go behind `if #available` (Liquid Glass
`glassEffect`, SwiftUI `WebView`, and so on) once you have confirmed the symbol.

## What HomePadCore gives you (read the sources, they are short)

`Packages/HomePadCore/Sources/HomePadCore/`

| Type | Use |
|---|---|
| `HouseholdProfile`, `RainbowTint` | A household member. `id: UUID` is the join key everywhere. |
| `HouseholdSession` (`@MainActor @Observable`) | Who is in front of the hub. `activeProfile`, `isGuest`, `isPersonalContentUnlocked`, `proximity`. The face package drives it with `faceRecognized`, `unknownFacePresent`, `presenceLost`. |
| `ProfileActivation` | `.manual` personalizes but keeps personal content locked. Only `.face` unlocks it. |
| `PeerChannel`, `PeerDevice`, `PeerEnvelope`, `PeerChannelName` | Authenticated hub and companion message transport. HomePadBeam implements it. Everything else consumes `any PeerChannel`. |
| `LoopbackPeerChannel` | In-process pair for tests and previews. |
| `HomePadIdentifiers` | Bundle prefix, app group, URL scheme, Bonjour type, activity types. Never hardcode these strings. |
| `DeviceRole` | `.hub` (iPad) or `.companion` (iPhone). |

Personal content rule, same as HomeView: personal content (messages, calendar, personal widgets)
shows on the hub only while `session.isPersonalContentUnlocked` is true, and only for content that
belongs to `session.activeProfile`. Everyone else gets the guest experience.

## Code rules

- `final` classes, `let` over `var`, no force unwraps, no `try!`, no `fatalError` in shipped paths.
- Narrow `catch` clauses. Typed, `Equatable` error enums.
- Comments state constraints the code cannot show. No comment that restates the line below it, no
  history, no measurements, no references to tickets, people, docs, or other apps. Doc comments
  are plain text.
- Never use em dashes or en dashes in comments, strings, or docs. US English.
- UI strings go through `String(localized:)` or SwiftUI `Text` literals.
- Accessibility: every control has a label; support Dynamic Type; hub text must be legible from
  across a room at `Proximity.far`.
- Test names: `method_whenCondition_thenOutcome`. Swift Testing (`import Testing`), not XCTest.
- Target 100% line coverage of `<Name>Core`. Cover failure paths. Report the real number.
- A test that still passes with the bug put back proves nothing. For at least your two most
  important behaviors, break the code, watch the test fail, and restore it. Say which ones.

## Final report (your last message)

1. Files you created, as a tree.
2. Public API the app target needs to call, with exact type and initializer signatures.
3. `Info.plist` keys, entitlements, capabilities, and background modes your code needs.
4. What you verified (commands run, results, coverage number) and what you could not verify.
5. Known gaps and anything the platform does not allow.
