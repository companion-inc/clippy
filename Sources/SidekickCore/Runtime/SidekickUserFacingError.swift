import Foundation

public enum SidekickUserFacingError {
    public enum ProviderLimit: Equatable, Sendable {
        case claude
        case chatGPT
        case xAI
        case unknown
    }

    public enum ProviderIssue: Equatable, Sendable {
        case usageLimit(ProviderLimit)
        case authentication(ProviderLimit)
        case connection(ProviderLimit)

        public var provider: ProviderLimit {
            switch self {
            case .usageLimit(let provider), .authentication(let provider), .connection(let provider):
                return provider
            }
        }

        public var isUsageLimit: Bool {
            if case .usageLimit = self { return true }
            return false
        }
    }

    public static func replacement(for technicalText: String, isError: Bool) -> String? {
        if let providerLimit = providerLimitMessage(for: technicalText) {
            return providerLimit
        }
        if let providerAuthentication = providerAuthenticationMessage(for: technicalText) {
            return providerAuthentication
        }
        if let providerConnection = providerConnectionMessage(for: technicalText) {
            return providerConnection
        }
        if isError {
            return message(for: technicalText)
        }
        if isTechnicalComputerUseFallback(technicalText) {
            return "Computer-control error. Details saved in Sidekick Logs."
        }
        return nil
    }

    public static func message(for technicalText: String) -> String {
        let lower = technicalText.lowercased()
        if containsAny(lower, ["cua", "computer-use", "mcp", "tool", "browser", "click", "type"]) {
            return "Computer-control error. Details saved in Sidekick Logs."
        }
        if containsAny(lower, [
            "anthropic",
            "app-server",
            "chatgpt",
            "claude",
            "codex",
            "connection closed",
            "connection timed out",
            "couldn't stream",
            "model",
            "openai",
            "returned nothing",
            "stream",
            "timed out",
            "timeout",
        ]) {
            return "Brain error. Details saved in Sidekick Logs."
        }
        return "Local error. Details saved in Sidekick Logs."
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

    public static func providerLimit(for text: String) -> ProviderLimit? {
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
            return .claude
        }
        if lower.contains("chatgpt") || lower.contains("openai") || lower.contains("codex") {
            return .chatGPT
        }
        if lower.contains("xai") || lower.contains("grok") {
            return .xAI
        }
        return .unknown
    }

    public static func providerIssue(for text: String) -> ProviderIssue? {
        if let limit = providerLimit(for: text) {
            return .usageLimit(limit)
        }
        if let authentication = providerAuthentication(for: text) {
            return .authentication(authentication)
        }
        if let connection = providerConnection(for: text) {
            return .connection(connection)
        }
        return nil
    }

    public static func providerAuthentication(for text: String) -> ProviderLimit? {
        let lower = text.lowercased()
        guard containsAny(lower, [
            "api error: 401",
            "authorizationrequired",
            "failed to authenticate",
            "invalid authentication credentials",
            "invalid_grant",
            "re-authorization required",
            "unauthenticated",
        ]) else {
            return nil
        }
        if lower.contains("claude") || lower.contains("anthropic") {
            return .claude
        }
        if lower.contains("chatgpt") || lower.contains("openai") || lower.contains("codex") {
            return .chatGPT
        }
        if lower.contains("xai") || lower.contains("grok") {
            return .xAI
        }
        return .unknown
    }

    public static func providerConnection(for text: String) -> ProviderLimit? {
        let lower = text.lowercased()
        guard containsAny(lower, [
            "connection closed",
            "connection timed out",
            "couldn't stream",
            "returned nothing",
            "stream disconnected",
            "timed out",
            "timeout",
        ]) else {
            return nil
        }
        if lower.contains("claude") || lower.contains("anthropic") {
            return .claude
        }
        if lower.contains("chatgpt") || lower.contains("openai") || lower.contains("codex") {
            return .chatGPT
        }
        if lower.contains("xai") || lower.contains("grok") {
            return .xAI
        }
        return .unknown
    }

    private static func providerLimitMessage(for text: String) -> String? {
        guard let providerLimit = providerLimit(for: text) else {
            return nil
        }
        switch providerLimit {
        case .claude:
            return "Claude usage limit hit. Raise it at claude.ai/settings/usage."
        case .chatGPT:
            return "ChatGPT usage limit hit. Check billing or usage settings."
        case .xAI:
            return "xAI usage limit hit. Check xAI billing or credits."
        case .unknown:
            return "Usage limit hit. Check the account billing or usage settings."
        }
    }

    private static func providerAuthenticationMessage(for text: String) -> String? {
        guard let provider = providerAuthentication(for: text) else {
            return nil
        }
        switch provider {
        case .claude:
            return "Claude sign-in expired. Sign in again or switch to ChatGPT."
        case .chatGPT:
            return "ChatGPT sign-in expired. Sign in again or switch to Claude."
        case .xAI:
            return "xAI sign-in expired. Check xAI credentials."
        case .unknown:
            return "Brain sign-in expired. Sign in again or switch models."
        }
    }

    private static func providerConnectionMessage(for text: String) -> String? {
        guard let provider = providerConnection(for: text) else {
            return nil
        }
        switch provider {
        case .claude:
            return "Claude timed out. Try again or switch to ChatGPT."
        case .chatGPT:
            return "ChatGPT timed out. Try again or switch to Claude."
        case .xAI:
            return "xAI timed out. Try again."
        case .unknown:
            return "Brain timed out. Try again or switch models."
        }
    }
}
