import Foundation

/// An xAI Grok TTS voice Clippy can speak with.
public struct ClippyVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let gender: String

    public init(id: String, displayName: String, gender: String) {
        self.id = id
        self.displayName = displayName
        self.gender = gender
    }
}

public extension ClippyVoice {
    static let eve = ClippyVoice(id: "eve", displayName: "Energetic, upbeat", gender: "Female")
    static let ara = ClippyVoice(id: "ara", displayName: "Warm, friendly", gender: "Female")
    static let sal = ClippyVoice(id: "sal", displayName: "Smooth, balanced", gender: "Male")
    static let rex = ClippyVoice(id: "rex", displayName: "Confident, clear", gender: "Male")
    static let leo = ClippyVoice(id: "leo", displayName: "Authoritative, strong", gender: "Male")

    static let all: [ClippyVoice] = [eve, ara, sal, rex, leo]

    static let `default` = eve

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
