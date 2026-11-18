// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

var products: [Product] = [.library(name: "HomePadBeamCore", targets: ["HomePadBeamCore"])]
var targets: [Target] = [
    .target(name: "HomePadBeamCore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
    .testTarget(name: "HomePadBeamCoreTests", dependencies: ["HomePadBeamCore"]),
]
var dependencies: [Package.Dependency] = [.package(path: "../HomePadCore")]
if !hostTests {
    dependencies.append(.package(path: "../HomePadAnimations"))
    products.append(.library(name: "HomePadBeam", targets: ["HomePadBeam"]))
    targets.append(.target(name: "HomePadBeam", dependencies: [
        "HomePadBeamCore",
        .product(name: "HomePadCore", package: "HomePadCore"),
        .product(name: "HomePadAnimations", package: "HomePadAnimations"),
        .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
    ]))
}

let package = Package(
    name: "HomePadBeam",
    platforms: platforms,
    products: products,
    dependencies: dependencies,
    targets: targets
)
