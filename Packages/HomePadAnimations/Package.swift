// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]
let lottie = Target.Dependency.product(name: "Lottie", package: "lottie-ios")

var products: [Product] = [.library(name: "HomePadAnimationsCore", targets: ["HomePadAnimationsCore"])]
var targets: [Target] = [
    .target(name: "HomePadAnimationsCore", resources: [.process("Resources")]),
    .testTarget(name: "HomePadAnimationsCoreTests", dependencies: ["HomePadAnimationsCore", lottie]),
]
if !hostTests {
    products.append(.library(name: "HomePadAnimations", targets: ["HomePadAnimations"]))
    targets.append(.target(name: "HomePadAnimations", dependencies: ["HomePadAnimationsCore", lottie]))
}

let package = Package(
    name: "HomePadAnimations",
    platforms: platforms,
    products: products,
    dependencies: [.package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.6.1")],
    targets: targets
)
