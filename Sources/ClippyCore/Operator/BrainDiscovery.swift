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
    public static func claudeSignedIn() -> Bool {
        guard LocalCLIConversation.locateBinary() != nil else { return false }
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty == false { return true }
        return anyFileExists([".claude/.credentials.json", ".claude.json"])
    }

    public static func codexSignedIn() -> Bool {
        guard CodexConversation.locateBinary() != nil else { return false }
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false { return true }
        return anyFileExists([".codex/auth.json"])
    }

    /// The brain to use when the user hasn't picked one yet: whichever subscription
    /// is present. If both are signed in, prefer Opus 4.8 (the stronger driver); if
    /// neither, fall back to Opus so the UI can report "brain not installed".
    public static func defaultModel() -> ClippyModel {
        if claudeSignedIn() { return .opus48 }
        if codexSignedIn() { return .gpt55 }
        return .opus48
    }

    private static func anyFileExists(_ relativePaths: [String]) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return relativePaths.contains { FileManager.default.fileExists(atPath: "\(home)/\($0)") }
    }
}
