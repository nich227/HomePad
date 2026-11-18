// swift-tools-version: 6.2
import PackageDescription

let lottie = Target.Dependency.product(name: "Lottie", package: "lottie-ios")

let package = Package(
    name: "HomePadAnimations",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HomePadAnimationsCore", targets: ["HomePadAnimationsCore"]),
        .library(name: "HomePadAnimations", targets: ["HomePadAnimations"]),
    ],
    dependencies: [.package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.6.1")],
    targets: [
        .target(name: "HomePadAnimationsCore", resources: [.process("Resources")]),
        .target(name: "HomePadAnimations", dependencies: ["HomePadAnimationsCore", lottie]),
        .testTarget(name: "HomePadAnimationsCoreTests", dependencies: ["HomePadAnimationsCore", lottie]),
    ]
)
