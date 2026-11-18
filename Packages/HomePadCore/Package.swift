// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadCore",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HomePadCore", targets: ["HomePadCore"]),
    ],
    targets: [
        .target(name: "HomePadCore"),
        .testTarget(name: "HomePadCoreTests", dependencies: ["HomePadCore"]),
    ]
)
