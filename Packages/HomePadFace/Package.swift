// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadFace",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadFaceCore", targets: ["HomePadFaceCore"]),
        .library(name: "HomePadFace", targets: ["HomePadFace"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadAnimations"),
    ],
    targets: [
        .target(name: "HomePadFaceCore", dependencies: [.product(name: "HomePadCore", package: "HomePadCore")]),
        .target(
            name: "HomePadFace",
            dependencies: [
                "HomePadFaceCore",
                .product(name: "HomePadCore", package: "HomePadCore"),
                .product(name: "HomePadAnimations", package: "HomePadAnimations"),
                .product(name: "HomePadAnimationsCore", package: "HomePadAnimations"),
            ]
        ),
        .testTarget(
            name: "HomePadFaceCoreTests",
            dependencies: ["HomePadFaceCore", .product(name: "HomePadCore", package: "HomePadCore")]
        ),
    ]
)
