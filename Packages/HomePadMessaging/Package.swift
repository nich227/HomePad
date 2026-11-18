// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadMessaging",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadMessagingCore", targets: ["HomePadMessagingCore"]),
        .library(name: "HomePadMessaging", targets: ["HomePadMessaging"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadAnimations"),
    ],
    targets: [
        .target(
            name: "HomePadMessagingCore",
            dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]
        ),
        .target(
            name: "HomePadMessaging",
            dependencies: [
                "HomePadMessagingCore",
                .product(name: "HomePadCore", package: "HomePadCore"),
                .product(name: "HomePadAnimations", package: "HomePadAnimations"),
                .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
            ]
        ),
        .testTarget(
            name: "HomePadMessagingCoreTests",
            dependencies: ["HomePadMessagingCore", .product(name: "HomePadCore", package: "HomePadCore")]
        ),
    ]
)
