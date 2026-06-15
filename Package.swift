// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Clippy", targets: ["Clippy"]),
        .executable(name: "ClippyMCP", targets: ["ClippyMCP"]),
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
        .executableTarget(
            name: "ClippyMCP"
        ),
        .testTarget(
            name: "ClippyTests",
            dependencies: ["ClippyCore"]
        ),
    ]
)
