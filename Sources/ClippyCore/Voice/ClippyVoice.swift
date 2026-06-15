import Foundation

/// A Deepgram Aura-2 voice Clippy can speak with. Curated to characterful,
/// mostly-masculine voices that suit a cheeky, helpful paperclip (Thalia, the
/// iris/clippy default, is kept as an option but isn't the default here).
public struct ClippyVoice: Equatable, Sendable, Identifiable {
    public let id: String          // Deepgram model id, e.g. "aura-2-aries-en"
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public extension ClippyVoice {
    static let aries = ClippyVoice(id: "aura-2-aries-en", displayName: "Aries — warm, energetic")
    static let atlas = ClippyVoice(id: "aura-2-atlas-en", displayName: "Atlas — enthusiastic, friendly")
    static let apollo = ClippyVoice(id: "aura-2-apollo-en", displayName: "Apollo — confident, casual")
    static let arcas = ClippyVoice(id: "aura-2-arcas-en", displayName: "Arcas — natural, smooth")
    static let draco = ClippyVoice(id: "aura-2-draco-en", displayName: "Draco — British baritone")
    static let hermes = ClippyVoice(id: "aura-2-hermes-en", displayName: "Hermes — expressive")
    static let thalia = ClippyVoice(id: "aura-2-thalia-en", displayName: "Thalia — clear, energetic (f)")

    static let all: [ClippyVoice] = [aries, atlas, apollo, arcas, draco, hermes, thalia]

    /// Default Clippy voice — warm + energetic, casual-chat tuned.
    static let `default` = aries

    static func by(id: String) -> ClippyVoice? {
        all.first { $0.id == id }
    }
}
