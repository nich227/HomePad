// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadUI",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HomePadUICore", targets: ["HomePadUICore"]),
        .library(name: "HomePadUI", targets: ["HomePadUI"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadAnimations"),
    ],
    targets: [
        .target(name: "HomePadUICore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
        .target(name: "HomePadUI", dependencies: [
            "HomePadUICore",
            .product(name: "HomePadCore", package: "HomePadCore"),
            .product(name: "HomePadAnimations", package: "HomePadAnimations"),
            .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
        ]),
        .testTarget(name: "HomePadUICoreTests", dependencies: ["HomePadUICore"]),
    ]
)
