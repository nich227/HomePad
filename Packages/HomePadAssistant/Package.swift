// swift-tools-version: 6.2
import PackageDescription

let core = Target.Dependency.product(name: "HomePadCore", package: "HomePadCore")

let package = Package(
    name: "HomePadAssistant",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HomePadAssistantCore", targets: ["HomePadAssistantCore"]),
        .library(name: "HomePadAssistant", targets: ["HomePadAssistant"]),
    ],
    dependencies: [.package(path: "../HomePadCore")],
    targets: [
        .target(name: "HomePadAssistantCore", dependencies: [core]),
        .target(name: "HomePadAssistant", dependencies: ["HomePadAssistantCore", core]),
        .testTarget(name: "HomePadAssistantCoreTests", dependencies: ["HomePadAssistantCore", core]),
    ]
)
