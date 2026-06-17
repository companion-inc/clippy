import Foundation

public struct BrainFallbackOffer: Equatable, Sendable {
    public let fromProviderName: String
    public let toProviderName: String
    public let toModel: ClippyModel

    public var prompt: String {
        "\(fromProviderName) usage limit hit. Switch to \(toProviderName)?"
    }

    public var actionTitle: String {
        "Switch to \(toProviderName)"
    }

    public var keepTitle: String {
        "Keep \(fromProviderName)"
    }
}

public enum BrainFallbackPolicy {
    public static func offer(
        afterProviderLimitText text: String,
        attemptedModel: ClippyModel,
        isChatGPTAvailable: Bool,
        isClaudeAvailable: Bool
    ) -> BrainFallbackOffer? {
        switch (attemptedModel.backend, ClippyUserFacingError.providerLimit(for: text)) {
        case (.claude, .claude?) where isChatGPTAvailable:
            return BrainFallbackOffer(
                fromProviderName: "Claude",
                toProviderName: "ChatGPT",
                toModel: .gpt55
            )
        case (.codex, .chatGPT?) where isClaudeAvailable:
            return BrainFallbackOffer(
                fromProviderName: "ChatGPT",
                toProviderName: "Claude",
                toModel: .opus48
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
