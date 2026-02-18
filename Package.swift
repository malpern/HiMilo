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
        .executableTarget(
            name: "HiMilo",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HiMilo",
            exclude: ["Resources"]
        ),
    ]
)
