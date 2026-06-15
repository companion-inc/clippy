import Foundation

/// A model the user can drive Clippy's brain with. `backend` picks the local CLI:
/// Claude models run through `claude`, GPT-5.5 through `codex app-server` — both at low effort.
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
    static let opus48 = ClippyModel(id: "claude-opus-4-8", displayName: "Opus 4.8", backend: .claude)
    static let gpt55 = ClippyModel(id: "gpt-5.5", displayName: "GPT 5.5", backend: .codex)

    /// The only two brains Clippy offers (right-click → Model), both at low effort.
    static let all: [ClippyModel] = [opus48, gpt55]

    /// Fallback driver when Codex is not signed in locally.
    static let `default` = opus48

    static func by(id: String) -> ClippyModel? {
        all.first { $0.id == id }
    }
}
