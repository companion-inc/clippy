import Foundation

public struct SidekickResourceManifest: Codable, Equatable, Sendable {
    public let id: String?
    public let displayName: String?
    public let sourceRoot: String
    public let outputRoot: String
    public let generatedAt: String
    public let frameSize: [Int]
    public let overlayCount: Int
    public let soundCount: Int
    public let animationCount: Int
    public let animations: [String]
}

public enum CharacterResourceLoader {
    public static func loadRasterPack(from root: URL) throws -> RasterCharacterPack {
        let data = try Data(contentsOf: root.appending(path: "character.json"))
        return try JSONDecoder().decode(RasterCharacterPack.self, from: data)
    }

    public static func loadManifest(from root: URL) throws -> SidekickResourceManifest {
        let data = try Data(contentsOf: root.appending(path: "manifest.json"))
        return try JSONDecoder().decode(SidekickResourceManifest.self, from: data)
    }

    public static func packDescriptor(from root: URL, id: String, displayName: String) throws -> CharacterPack {
        let pack = try loadRasterPack(from: root)
        return CharacterPack(
            id: id,
            displayName: displayName,
            defaultSize: CharacterSize(
                width: Double(pack.frameSize.first ?? 124),
                height: Double(pack.frameSize.dropFirst().first ?? 93)
            ),
            renderMode: .raster,
            bubbleAnchor: CharacterPoint(x: 0.5, y: 1.0),
            dragAnchor: CharacterPoint(x: 0.5, y: 0.5),
            defaultAnimationByState: [
                .showing: "Show",
                .idle: "RestPose",
                .hearing: "Hearing_1",
                .thinking: "Thinking",
                .screenVision: "Searching",
                .cameraVision: "LookUp",
                .reading: "LookDown",
                .searching: "Searching",
                .writing: "Writing",
                .computerControl: "Processing",
                .waitingApproval: "IdleEyeBrowRaise",
                .done: "Congratulate",
                .blocked: "Alert",
                .error: "Alert",
            ]
        )
    }

    public static func packDescriptor(from root: URL, spec: SidekickSpec) throws -> CharacterPack {
        try packDescriptor(from: root, id: spec.id, displayName: spec.displayName)
    }

    public static func sidekickPackDescriptor(from root: URL) throws -> CharacterPack {
        try packDescriptor(from: root, spec: .clippy)
    }
}
