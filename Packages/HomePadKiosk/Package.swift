// swift-tools-version: 6.2
import PackageDescription

let core = Target.Dependency.product(name: "HomePadCore", package: "HomePadCore")

let package = Package(
    name: "HomePadKiosk",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadKioskCore", targets: ["HomePadKioskCore"]),
        .library(name: "HomePadKiosk", targets: ["HomePadKiosk"]),
    ],
    dependencies: [.package(path: "../HomePadCore")],
    targets: [
        .target(name: "HomePadKioskCore", dependencies: [core]),
        .target(name: "HomePadKiosk", dependencies: ["HomePadKioskCore", core]),
        .testTarget(name: "HomePadKioskCoreTests", dependencies: ["HomePadKioskCore"]),
    ]
)
