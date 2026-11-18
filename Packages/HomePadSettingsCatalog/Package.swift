// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

// Every package that declares settings. Only their pure Core targets are linked, so the catalog
// builds on the Mac host, where the Settings bundle generator runs.
let features = ["HomePadKiosk", "HomePadFace", "HomePadBeam", "HomePadMessaging", "HomePadUI"]

var targets: [Target] = [
    .target(
        name: "HomePadSettingsCatalog",
        dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]
            + features.map { .product(name: "\($0)Core", package: $0) }
    ),
    .testTarget(name: "HomePadSettingsCatalogTests", dependencies: ["HomePadSettingsCatalog"]),
]
if hostTests {
    targets.append(.executableTarget(name: "homepad-settings", dependencies: ["HomePadSettingsCatalog"]))
}

let package = Package(
    name: "HomePadSettingsCatalog",
    platforms: platforms,
    products: [.library(name: "HomePadSettingsCatalog", targets: ["HomePadSettingsCatalog"])],
    dependencies: [.package(path: "../HomePadCore")] + features.map { .package(path: "../\($0)") },
    targets: targets
)
