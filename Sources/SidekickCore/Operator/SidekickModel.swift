import Foundation

/// A model Sidekick can route work through. `backend` picks the local CLI:
/// Claude models run through `claude`; GPT models run through `codex app-server`.
public struct SidekickModel: Equatable, Sendable, Identifiable {
    public enum Backend: String, Equatable, Hashable, Sendable {
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

public extension SidekickModel {
    static let opus48 = SidekickModel(id: "claude-opus-4-8", displayName: "Opus 4.8", backend: .claude)
    static let gpt55 = SidekickModel(id: "gpt-5.5", displayName: "GPT 5.5", backend: .codex)
    static let gpt54 = SidekickModel(id: "gpt-5.4", displayName: "GPT 5.4", backend: .codex)
    static let gpt54Mini = SidekickModel(id: "gpt-5.4-mini", displayName: "GPT 5.4 Mini", backend: .codex)
    static let sonnet46 = SidekickModel(id: "claude-sonnet-4-6", displayName: "Sonnet 4.6", backend: .claude)
    static let haiku45 = SidekickModel(id: "claude-haiku-4-5", displayName: "Haiku 4.5", backend: .claude)

    /// The only two executor brains Sidekick offers in the visible right-click Model menu.
    static let all: [SidekickModel] = [opus48, gpt55]

    static func notificationWakeModel(for backend: Backend) -> SidekickModel {
        switch backend {
        case .claude: return .haiku45
        case .codex: return .gpt54Mini
        }
    }

    static func recommendationModel(for backend: Backend) -> SidekickModel {
        switch backend {
        case .claude: return .sonnet46
        case .codex: return .gpt54
        }
    }

    /// Fallback driver when Codex is not signed in locally.
    static let `default` = opus48

    static func by(id: String) -> SidekickModel? {
        all.first { $0.id == id }
    }
}

public enum SidekickHiddenBrainRole: Equatable, Sendable {
    case backgroundScreenWake
    case invocationRecommendations
}

public enum SidekickHiddenBrainRouting {
    public static func backendPreference(
        selectedModel: SidekickModel,
        role: SidekickHiddenBrainRole
    ) -> [SidekickModel.Backend] {
        switch role {
        case .backgroundScreenWake:
            switch selectedModel.backend {
            case .claude: return [.claude, .codex]
            case .codex: return [.codex, .claude]
            }
        case .invocationRecommendations:
            switch selectedModel.backend {
            case .claude: return [.claude, .codex]
            case .codex: return [.codex, .claude]
            }
        }
    }
}
