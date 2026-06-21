// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sidekick",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sidekick", targets: ["Sidekick"]),
        .executable(name: "SidekickMCP", targets: ["SidekickMCP"]),
        .executable(name: "SidekickRecordReplayMCP", targets: ["SidekickRecordReplayMCP"]),
        .library(name: "SidekickCore", targets: ["SidekickCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.3"),
    ],
    targets: [
        .target(
            name: "SidekickCore"
        ),
        .executableTarget(
            name: "Sidekick",
            dependencies: [
                "SidekickCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "SidekickMCP",
            dependencies: ["SidekickCore"]
        ),
        .executableTarget(
            name: "SidekickRecordReplayMCP",
            dependencies: ["SidekickCore"]
        ),
        .testTarget(
            name: "SidekickTests",
            dependencies: ["SidekickCore"]
        ),
    ]
)
