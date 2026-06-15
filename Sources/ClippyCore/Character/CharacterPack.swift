import Foundation

public enum CharacterRenderMode: String, Codable, Equatable, Sendable {
    case raster
}

public struct CharacterPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CharacterSize: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CharacterPack: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let defaultSize: CharacterSize
    public let renderMode: CharacterRenderMode
    public let bubbleAnchor: CharacterPoint
    public let dragAnchor: CharacterPoint
    public let defaultAnimationByState: [MascotState: String]

    public init(
        id: String,
        displayName: String,
        defaultSize: CharacterSize,
        renderMode: CharacterRenderMode,
        bubbleAnchor: CharacterPoint,
        dragAnchor: CharacterPoint,
        defaultAnimationByState: [MascotState: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultSize = defaultSize
        self.renderMode = renderMode
        self.bubbleAnchor = bubbleAnchor
        self.dragAnchor = dragAnchor
        self.defaultAnimationByState = defaultAnimationByState
    }
}
