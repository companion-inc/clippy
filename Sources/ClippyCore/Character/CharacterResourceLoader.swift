import Foundation

public struct ClippitResourceManifest: Codable, Equatable, Sendable {
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

    public static func loadManifest(from root: URL) throws -> ClippitResourceManifest {
        let data = try Data(contentsOf: root.appending(path: "manifest.json"))
        return try JSONDecoder().decode(ClippitResourceManifest.self, from: data)
    }

    public static func clippitPackDescriptor(from root: URL) throws -> CharacterPack {
        let pack = try loadRasterPack(from: root)
        return CharacterPack(
            id: "clippit",
            displayName: "Clippy",
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
}
