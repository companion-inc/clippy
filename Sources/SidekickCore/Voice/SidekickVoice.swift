import Foundation

/// An xAI Grok TTS voice Sidekick can speak with.
public struct SidekickVoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let detail: String

    public init(id: String, displayName: String, detail: String) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
    }
}

public extension SidekickVoice {
    static let ara = SidekickVoice(id: "ara", displayName: "Ara", detail: "Female · Bright")
    static let rex = SidekickVoice(id: "rex", displayName: "Rex", detail: "Male · Calm")

    static let all: [SidekickVoice] = [ara, rex]

    static let `default` = ara

    static func by(id: String) -> SidekickVoice? {
        all.first { $0.id == id }
    }
}
