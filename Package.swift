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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3"),
    ],
    targets: [
        .target(
            name: "ClippyCore"
        ),
        .executableTarget(
            name: "Clippy",
            dependencies: [
                "ClippyCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "ClippyMCP",
            dependencies: ["ClippyCore"]
        ),
        .testTarget(
            name: "ClippyTests",
            dependencies: ["ClippyCore"]
        ),
    ]
)
