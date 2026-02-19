// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HiMilo",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "HiMiloCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HiMiloCore",
            exclude: ["Resources"],
            resources: [
                .copy("Audio/Samples/onyx-sample.mp3"),
            ]
        ),
        .executableTarget(
            name: "HiMilo",
            dependencies: ["HiMiloCore"],
            path: "Sources/HiMilo"
        ),
        .testTarget(
            name: "HiMiloCoreTests",
            dependencies: ["HiMiloCore"],
            path: "Tests/HiMiloCoreTests"
        ),
    ]
)
