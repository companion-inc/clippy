import Foundation

/// A model the user can drive Clippy's brain with. `backend` picks the local CLI:
/// Claude models run through `claude`, GPT-5.5 through `codex exec` — both at low effort.
public struct ClippyModel: Equatable, Sendable, Identifiable {
    public enum Backend: String, Equatable, Sendable {
        case claude
        case codex
    }

    public let id: String          // CLI model id (claude `--model` / codex `-m`)
    public let displayName: String
    public let backend: Backend

    public init(id: String, displayName: String, backend: Backend) {
        self.id = id
        self.displayName = displayName
        self.backend = backend
    }
}

public extension ClippyModel {
    static let opus48 = ClippyModel(id: "claude-opus-4-8", displayName: "Claude Opus 4.8", backend: .claude)
    static let gpt55 = ClippyModel(id: "gpt-5.5", displayName: "GPT-5.5 (Codex)", backend: .codex)
    static let sonnet46 = ClippyModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", backend: .claude)
    static let haiku45 = ClippyModel(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5", backend: .claude)

    /// Offered in the Model picker (right-click → Model).
    static let all: [ClippyModel] = [opus48, gpt55, sonnet46, haiku45]

    /// Default driver: Opus 4.8 — the best computer-use model per the migration research.
    static let `default` = opus48

    static func by(id: String) -> ClippyModel? {
        all.first { $0.id == id }
    }
}
