// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "LidAwake",
            path: "Sources/LidAwake"
        )
    ]
)
