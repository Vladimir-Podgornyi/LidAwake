// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "LidAwakeCore",
            path: "Sources/LidAwakeCore"
        ),
        .executableTarget(
            name: "LidAwake",
            dependencies: ["LidAwakeCore"],
            path: "Sources/LidAwake"
        ),
        .testTarget(
            name: "LidAwakeCoreTests",
            dependencies: ["LidAwakeCore"],
            path: "Tests/LidAwakeCoreTests"
        )
    ]
)
