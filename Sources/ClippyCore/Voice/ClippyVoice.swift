import Foundation

/// An xAI Grok TTS voice Clippy can speak with.
public struct ClippyVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let detail: String

    public init(id: String, displayName: String, detail: String) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
    }
}

public extension ClippyVoice {
    static let ara = ClippyVoice(id: "ara", displayName: "Ara", detail: "Female · Bright")
    static let rex = ClippyVoice(id: "rex", displayName: "Rex", detail: "Male · Calm")

    static let all: [ClippyVoice] = [ara, rex]

    static let `default` = ara

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
