import Foundation

public enum ClippyUserFacingError {
    public static func replacement(for technicalText: String, isError: Bool) -> String? {
        if let providerLimit = providerLimitMessage(for: technicalText) {
            return providerLimit
        }
        if isError {
            return message(for: technicalText)
        }
        if isTechnicalComputerUseFallback(technicalText) {
            return "Computer-control error. Details saved in Clippy Logs."
        }
        return nil
    }

    public static func message(for technicalText: String) -> String {
        let lower = technicalText.lowercased()
        if containsAny(lower, ["cua", "computer-use", "mcp", "tool", "browser", "click", "type"]) {
            return "Computer-control error. Details saved in Clippy Logs."
        }
        if containsAny(lower, ["codex", "app-server", "model", "stream"]) {
            return "Brain error. Details saved in Clippy Logs."
        }
        return "Local error. Details saved in Clippy Logs."
    }

    public static func isTechnicalComputerUseFallback(_ text: String) -> Bool {
        let lower = text.lowercased()
        let mentionsInternalComputerUse = containsAny(lower, [
            "cua",
            "computer-use bridge",
            "computer use bridge",
            "mcp",
        ])
        let givesUpOrHandsOff = containsAny(lower, [
            "not connected",
            "isn't connected",
            "is not connected",
            "not available",
            "unavailable",
            "can't click",
            "cannot click",
            "can't type",
            "cannot type",
            "start the computer-use bridge",
            "start the computer use bridge",
            "start the bridge",
        ])
        return mentionsInternalComputerUse && givesUpOrHandsOff
    }

    private static func containsAny(_ lowercasedText: String, _ needles: [String]) -> Bool {
        needles.contains { lowercasedText.contains($0) }
    }

    private static func providerLimitMessage(for text: String) -> String? {
        let lower = text.lowercased()
        guard containsAny(lower, [
            "monthly spend limit",
            "spend limit",
            "usage limit",
            "rate limit",
            "insufficient credits",
        ]) else {
            return nil
        }
        if lower.contains("claude") || lower.contains("anthropic") {
            return "Claude usage limit hit. Raise it at claude.ai/settings/usage."
        }
        if lower.contains("chatgpt") || lower.contains("openai") || lower.contains("codex") {
            return "ChatGPT usage limit hit. Check billing or usage settings."
        }
        if lower.contains("xai") || lower.contains("grok") {
            return "xAI usage limit hit. Check xAI billing or credits."
        }
        return "Usage limit hit. Check the account billing or usage settings."
    }
}
