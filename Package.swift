// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "LidAwakeShared",
            path: "Sources/LidAwakeShared"
        ),
        .target(
            name: "LidAwakeCore",
            dependencies: ["LidAwakeShared"],
            path: "Sources/LidAwakeCore"
        ),
        .executableTarget(
            name: "LidAwake",
            dependencies: ["LidAwakeCore", "LidAwakeShared"],
            path: "Sources/LidAwake"
        ),
        .executableTarget(
            name: "LidAwakeHelper",
            dependencies: ["LidAwakeShared"],
            path: "Sources/LidAwakeHelper"
        ),
        .testTarget(
            name: "LidAwakeCoreTests",
            dependencies: ["LidAwakeCore"],
            path: "Tests/LidAwakeCoreTests"
        ),
        .testTarget(
            name: "LidAwakeSharedTests",
            dependencies: ["LidAwakeShared"],
            path: "Tests/LidAwakeSharedTests"
        )
    ]
)
