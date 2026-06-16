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
    static let eve = ClippyVoice(id: "eve", displayName: "Eve - energetic")
    static let ara = ClippyVoice(id: "ara", displayName: "Ara - warm")
    static let rex = ClippyVoice(id: "rex", displayName: "Rex - clear")
    static let sal = ClippyVoice(id: "sal", displayName: "Sal - smooth")
    static let leo = ClippyVoice(id: "leo", displayName: "Leo - authoritative")

    static let all: [ClippyVoice] = [eve, ara, rex, sal, leo]

    static let `default` = eve

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
