import Foundation

/// An xAI Grok TTS voice Clippy can speak with.
public struct ClippyVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public extension ClippyVoice {
    static let eve = ClippyVoice(id: "eve", displayName: "Clippy - bright")
    static let ara = ClippyVoice(id: "ara", displayName: "Clippy - friendly")
    static let sal = ClippyVoice(id: "sal", displayName: "Clippy - balanced")
    static let rex = ClippyVoice(id: "rex", displayName: "Clippy - clear")
    static let leo = ClippyVoice(id: "leo", displayName: "Clippy - steady")

    static let all: [ClippyVoice] = [eve, ara, sal, rex, leo]

    static let `default` = eve

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
