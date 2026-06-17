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
    static let eve = ClippyVoice(id: "eve", displayName: "Eve", detail: "Female · Multilingual")
    static let leo = ClippyVoice(id: "leo", displayName: "Leo", detail: "Male · Multilingual")

    static let all: [ClippyVoice] = [eve, leo]

    static let `default` = eve

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
