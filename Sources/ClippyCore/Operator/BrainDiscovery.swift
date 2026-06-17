import Foundation

/// Figures out which AI subscription the user actually has signed in locally, so
/// Clippy can default to the right brain out of the box instead of assuming one.
///
/// "Signed in" = the CLI binary is installed AND its login artifact is on disk:
///   • Claude Code → `~/.claude/.credentials.json` or `~/.claude.json` (its config,
///     written once you've set it up), or an `ANTHROPIC_API_KEY` in the environment.
///   • Codex (GPT) → `~/.codex/auth.json` (the OAuth token it writes on login).
/// We deliberately check files, not the Keychain, so detection never pops a
/// "Clippy wants to use a credential" prompt.
public enum BrainDiscovery {
    public struct Status: Equatable, Sendable {
        public let backend: ClippyModel.Backend
        public let binaryPath: String?
        public let signedIn: Bool

        public var isInstalled: Bool {
            binaryPath != nil
        }

        public var statusText: String {
            if signedIn { return "Ready" }
            if isInstalled { return "Installed, not signed in" }
            return "Not installed"
        }
    }

    public static func claudeStatus() -> Status {
        let path = LocalCLIConversation.locateBinary()
        return Status(backend: .claude, binaryPath: path, signedIn: claudeSignedIn(binaryPath: path))
    }

    public static func codexStatus() -> Status {
        let path = CodexConversation.locateBinary()
        return Status(backend: .codex, binaryPath: path, signedIn: codexSignedIn(binaryPath: path))
    }

    public static func anyBrainSignedIn() -> Bool {
        codexSignedIn() || claudeSignedIn()
    }

    public static func claudeSignedIn() -> Bool {
        claudeSignedIn(binaryPath: LocalCLIConversation.locateBinary())
    }

    private static func claudeSignedIn(binaryPath: String?) -> Bool {
        guard binaryPath != nil else { return false }
        if ClippySecrets.anthropicAPIKey != nil { return true }
        return anyFileExists([".claude/.credentials.json", ".claude.json"])
    }

    public static func codexSignedIn() -> Bool {
        codexSignedIn(binaryPath: CodexConversation.locateBinary())
    }

    private static func codexSignedIn(binaryPath: String?) -> Bool {
        guard binaryPath != nil else { return false }
        if ClippySecrets.openAIAPIKey != nil { return true }
        return anyFileExists([".codex/auth.json"])
    }

    /// The brain to use when the user hasn't picked one yet: whichever subscription
    /// is present. If both are signed in, prefer Codex because Clippy wires Cua and
    /// its annotation MCP server through the Codex app-server path.
    public static func defaultModel() -> ClippyModel {
        if codexSignedIn() { return .gpt55 }
        if claudeSignedIn() { return .opus48 }
        return .opus48
    }

    private static func anyFileExists(_ relativePaths: [String]) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return relativePaths.contains { FileManager.default.fileExists(atPath: "\(home)/\($0)") }
    }
}
