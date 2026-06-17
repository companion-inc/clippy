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
    static let grace = ClippyVoice(id: "grace", displayName: "Grace", detail: "Female · English")
    static let daniel = ClippyVoice(id: "daniel", displayName: "Daniel", detail: "Male · English")

    static let all: [ClippyVoice] = [grace, daniel]

    static let `default` = grace

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
