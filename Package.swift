// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Clippy", targets: ["Clippy"]),
        .library(name: "ClippyCore", targets: ["ClippyCore"]),
    ],
    targets: [
        .target(
            name: "ClippyCore"
        ),
        .executableTarget(
            name: "Clippy",
            dependencies: ["ClippyCore"]
        ),
        .testTarget(
            name: "ClippyTests",
            dependencies: ["ClippyCore"]
        ),
    ]
)
