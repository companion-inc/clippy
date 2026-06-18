import Foundation

public struct BrainFallbackOffer: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case usageLimit
        case connection
    }

    public let fromProviderName: String
    public let toProviderName: String
    public let toModel: ClippyModel
    public let reason: Reason

    public var prompt: String {
        switch reason {
        case .usageLimit:
            return "\(fromProviderName) usage limit hit. Switch to \(toProviderName)?"
        case .connection:
            return "\(fromProviderName) timed out. Switch to \(toProviderName)?"
        }
    }

    public var actionTitle: String {
        "Switch to \(toProviderName)"
    }

    public var keepTitle: String {
        if reason == .connection {
            return "Keep and retry"
        }
        return "Keep \(fromProviderName)"
    }

    public var discardTitle: String {
        "Discard"
    }
}

public enum BrainFallbackPolicy {
    public static func offer(
        afterProviderLimitText text: String,
        attemptedModel: ClippyModel,
        isChatGPTAvailable: Bool,
        isClaudeAvailable: Bool
    ) -> BrainFallbackOffer? {
        offer(
            afterProviderIssueText: text,
            attemptedModel: attemptedModel,
            isChatGPTAvailable: isChatGPTAvailable,
            isClaudeAvailable: isClaudeAvailable
        )
    }

    public static func offer(
        afterProviderIssueText text: String,
        attemptedModel: ClippyModel,
        isChatGPTAvailable: Bool,
        isClaudeAvailable: Bool
    ) -> BrainFallbackOffer? {
        guard let issue = ClippyUserFacingError.providerIssue(for: text) else {
            return nil
        }
        let reason: BrainFallbackOffer.Reason = issue.isUsageLimit ? .usageLimit : .connection
        switch (attemptedModel.backend, issue.provider) {
        case (.claude, .claude), (.claude, .unknown):
            guard isChatGPTAvailable else { return nil }
            return BrainFallbackOffer(
                fromProviderName: "Claude",
                toProviderName: "ChatGPT",
                toModel: .gpt55,
                reason: reason
            )
        case (.codex, .chatGPT), (.codex, .unknown):
            guard isClaudeAvailable else { return nil }
            return BrainFallbackOffer(
                fromProviderName: "ChatGPT",
                toProviderName: "Claude",
                toModel: .opus48,
                reason: reason
            )
        default:
            return nil
        }
    }

    public static func shouldOfferChatGPTSwitch(
        afterProviderLimitText text: String,
        selectedModel: ClippyModel,
        isChatGPTAvailable: Bool
    ) -> Bool {
        offer(
            afterProviderLimitText: text,
            attemptedModel: selectedModel,
            isChatGPTAvailable: isChatGPTAvailable,
            isClaudeAvailable: false
        ) != nil
    }
}
