// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DellFansController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DellFansController",
            targets: ["DellFansController"]
        )
    ],
    targets: [
        .target(
            name: "DellFansCore",
            path: "Sources/DellFansCore"
        ),
        .executableTarget(
            name: "DellFansController",
            dependencies: ["DellFansCore"],
            path: "Sources/DellFansController"
        ),
        .testTarget(
            name: "DellFansCoreTests",
            dependencies: ["DellFansCore"],
            path: "Tests/DellFansCoreTests"
        )
    ]
)
