// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VoxClaw",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "VoxClawCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/VoxClawCore",
            exclude: ["Resources"],
            resources: [
                .copy("Audio/Samples/onyx-sample.mp3"),
            ]
        ),
        .executableTarget(
            name: "VoxClaw",
            dependencies: ["VoxClawCore"],
            path: "Sources/VoxClaw"
        ),
        .testTarget(
            name: "VoxClawCoreTests",
            dependencies: ["VoxClawCore"],
            path: "Tests/VoxClawCoreTests"
        ),
    ]
)
