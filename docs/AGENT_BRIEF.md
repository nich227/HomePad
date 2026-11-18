# HomePad: brief for agents building feature packages

HomePad is an iPadOS and iOS app that recreates Apple HomeView features on an iPad. The iPad is the
shared **hub**. Each household member's iPhone runs the same app as a **companion**.

Project root: `/Volumes/workplace/HomePad/src/HomePad`

## Invariants

1. iOS and iPadOS only, deployment target 26.0. No macOS, Catalyst, visionOS, tvOS, or watchOS code paths.
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
7. This machine is shared and already loaded. Build only through the two scripts below. Never run
   `xcodebuild` or `swift build` with default parallelism, and never run two builds at once.

## Package layout (every feature package)

```
Packages/<Name>/
  Package.swift
  Sources/<Name>Core/      pure logic: Foundation, CryptoKit, Accelerate, Observation only
  Sources/<Name>/          iOS frameworks, SwiftUI views, services
  Tests/<Name>CoreTests/   Swift Testing, runs on the Mac host
```

The Mac has **no iOS simulator runtime**, so unit tests run on the macOS host. That only works for
code with no UIKit, AVFoundation, Vision, GroupActivities, or other iOS-only imports. So put every
decision, state machine, codec, and policy in `<Name>Core` and keep `<Name>` a thin shell around
system frameworks. The iOS target is verified by compiling it for a device.

Use this manifest shape. The host-test switch drops the iOS-only target so `swift test` does not
try to compile UIKit code for macOS:

```swift
// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

var products: [Product] = [.library(name: "<Name>Core", targets: ["<Name>Core"])]
var targets: [Target] = [
    .target(name: "<Name>Core", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
    .testTarget(name: "<Name>CoreTests", dependencies: ["<Name>Core"]),
]
if !hostTests {
    products.append(.library(name: "<Name>", targets: ["<Name>"]))
    targets.append(.target(name: "<Name>", dependencies: ["<Name>Core", .product(name: "HomePadCore", package: "HomePadCore")]))
}

let package = Package(
    name: "<Name>",
    platforms: platforms,
    products: products,
    dependencies: [.package(path: "../HomePadCore")],
    targets: targets
)
```

## Commands

| Need | Command (from the project root) |
|---|---|
| Unit tests on the host, with coverage | `Scripts/test-package.sh <Name>` |
| Compile the package for an iOS device | `Scripts/build-package.sh <Name>` |
| Coverage JSON path | `cd Packages/<Name> && HOMEPAD_HOST_TESTS=1 swift test --show-codecov-path` |
| iOS SDK path, to check an API exists | `xcrun --sdk iphoneos --show-sdk-path` |

Both scripts are capped (`-j 3`, `nice`). Redirect long output to a file and grep it.
`Scripts/build-package.sh` builds the scheme named after the package. If your package has several
library products, xcodebuild generates a `<Name>-Package` scheme; if the plain scheme is missing,
tell me in your report and build with `-scheme <Name>-Package` using the same flags as the script.

When you are not sure an API exists in this SDK, check the `.swiftinterface` or header under the
SDK path before using it. Do not guess. iOS 26 and 27 APIs are fine to use (Liquid Glass
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
