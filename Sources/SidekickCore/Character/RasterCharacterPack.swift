import Foundation

public struct RasterCharacterPack: Decodable, Equatable {
    public let overlayCount: Int
    public let sounds: [String]
    public let frameSize: [Int]
    public let animations: [String: RasterAnimation]

    enum CodingKeys: String, CodingKey {
        case overlayCount
        case sounds
        case frameSize = "framesize"
        case animations
    }

    public var animationNames: [String] {
        animations.keys.sorted()
    }
}

public struct RasterAnimation: Decodable, Equatable {
    public let frames: [RasterFrame]
    public let useExitBranching: Bool?
}

public struct RasterFrame: Decodable, Equatable {
    public let duration: Int
    public let images: [[Int]]?
    public let sound: String?
    public let exitBranch: Int?
    public let branching: RasterBranching?
}

public struct RasterBranching: Decodable, Equatable {
    public let branches: [RasterBranch]
}

public struct RasterBranch: Decodable, Equatable {
    public let frameIndex: Int
    public let weight: Int
}
