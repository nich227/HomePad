// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadBeam",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HomePadBeamCore", targets: ["HomePadBeamCore"]),
        .library(name: "HomePadBeam", targets: ["HomePadBeam"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadAnimations"),
    ],
    targets: [
        .target(name: "HomePadBeamCore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
        .target(name: "HomePadBeam", dependencies: [
            "HomePadBeamCore",
            .product(name: "HomePadCore", package: "HomePadCore"),
            .product(name: "HomePadAnimations", package: "HomePadAnimations"),
            .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
        ]),
        .testTarget(name: "HomePadBeamCoreTests", dependencies: ["HomePadBeamCore"]),
    ]
)
