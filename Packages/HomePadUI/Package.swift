// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The product is iOS and iPadOS only. Scripts/test-package.sh sets HOMEPAD_HOST_TESTS so the pure
// logic target can be tested on the Mac that builds it; the SwiftUI target is dropped for that run.
let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

var products: [Product] = [.library(name: "HomePadUICore", targets: ["HomePadUICore"])]
var targets: [Target] = [
    .target(name: "HomePadUICore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
    .testTarget(name: "HomePadUICoreTests", dependencies: ["HomePadUICore"]),
]
if !hostTests {
    products.append(.library(name: "HomePadUI", targets: ["HomePadUI"]))
    targets.append(.target(name: "HomePadUI", dependencies: [
        "HomePadUICore",
        .product(name: "HomePadCore", package: "HomePadCore"),
        .product(name: "HomePadAnimations", package: "HomePadAnimations"),
        .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
    ]))
}

var dependencies: [Package.Dependency] = [.package(path: "../HomePadCore")]
if !hostTests {
    dependencies.append(.package(path: "../HomePadAnimations"))
}

let package = Package(
    name: "HomePadUI",
    platforms: platforms,
    products: products,
    dependencies: dependencies,
    targets: targets
)
