// swift-tools-version: 6.2
import Foundation
import PackageDescription

let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]
let core = Target.Dependency.product(name: "HomePadCore", package: "HomePadCore")

var products: [Product] = [.library(name: "HomePadKioskCore", targets: ["HomePadKioskCore"])]
var targets: [Target] = [
    .target(name: "HomePadKioskCore", dependencies: [core]),
    .testTarget(name: "HomePadKioskCoreTests", dependencies: ["HomePadKioskCore"]),
]
if !hostTests {
    products.append(.library(name: "HomePadKiosk", targets: ["HomePadKiosk"]))
    targets.append(.target(name: "HomePadKiosk", dependencies: ["HomePadKioskCore", core]))
}

let package = Package(
    name: "HomePadKiosk",
    platforms: platforms,
    products: products,
    dependencies: [.package(path: "../HomePadCore")],
    targets: targets
)
