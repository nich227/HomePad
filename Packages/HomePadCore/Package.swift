// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The product is iOS and iPadOS only. Scripts/test-package.sh sets HOMEPAD_HOST_TESTS so the unit
// tests can run on the Mac that builds them when no iOS simulator runtime is installed.
let hostTests = ProcessInfo.processInfo.environment["HOMEPAD_HOST_TESTS"] != nil
let platforms: [SupportedPlatform] = hostTests ? [.iOS(.v26), .macOS(.v26)] : [.iOS(.v26)]

let package = Package(
    name: "HomePadCore",
    platforms: platforms,
    products: [
        .library(name: "HomePadCore", targets: ["HomePadCore"]),
    ],
    targets: [
        .target(name: "HomePadCore"),
        .testTarget(name: "HomePadCoreTests", dependencies: ["HomePadCore"]),
    ]
)
