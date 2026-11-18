// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The product is iOS and iPadOS only. Scripts/test-package.sh sets HOMEPAD_HOST_TESTS so the pure
// logic in HomePadFaceCore can be tested on the Mac that builds it.
let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

var dependencies: [Package.Dependency] = [.package(path: "../HomePadCore")]
var products: [Product] = [.library(name: "HomePadFaceCore", targets: ["HomePadFaceCore"])]
var targets: [Target] = [
    .target(name: "HomePadFaceCore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
    .testTarget(
        name: "HomePadFaceCoreTests",
        dependencies: ["HomePadFaceCore", .product(name: "HomePadCore", package: "HomePadCore")]
    ),
]
if !hostTests {
    dependencies.append(.package(path: "../HomePadAnimations"))
    products.append(.library(name: "HomePadFace", targets: ["HomePadFace"]))
    targets.append(
        .target(
            name: "HomePadFace",
            dependencies: [
                "HomePadFaceCore",
                .product(name: "HomePadCore", package: "HomePadCore"),
                .product(name: "HomePadAnimations", package: "HomePadAnimations"),
                .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
            ]
        )
    )
}

let package = Package(
    name: "HomePadFace",
    platforms: platforms,
    products: products,
    dependencies: dependencies,
    targets: targets
)
