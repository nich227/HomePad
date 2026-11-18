// swift-tools-version: 6.2
import PackageDescription

// Every package that declares settings. The catalog links only their Core targets, because the
// descriptors live there.
let features = ["HomePadKiosk", "HomePadFace", "HomePadBeam", "HomePadMessaging", "HomePadUI"]

let package = Package(
    name: "HomePadSettingsCatalog",
    platforms: [.iOS("27.0")],
    products: [.library(name: "HomePadSettingsCatalog", targets: ["HomePadSettingsCatalog"])],
    dependencies: [.package(path: "../HomePadCore")] + features.map { .package(path: "../\($0)") },
    targets: [
        .target(
            name: "HomePadSettingsCatalog",
            dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]
                + features.map { .product(name: "\($0)Core", package: $0) }
        ),
        .testTarget(name: "HomePadSettingsCatalogTests", dependencies: ["HomePadSettingsCatalog"]),
    ]
)
