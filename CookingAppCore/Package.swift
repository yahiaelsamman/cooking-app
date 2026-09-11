// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CookingAppCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CookingAppCore",
            targets: ["CookingAppCore"]
        )
    ],
    targets: [
        .target(
            name: "CookingAppCore"
        ),
        .testTarget(
            name: "CookingAppCoreTests",
            dependencies: ["CookingAppCore"]
        )
    ]
)
