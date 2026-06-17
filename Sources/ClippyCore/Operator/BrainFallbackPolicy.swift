import Foundation

public enum BrainFallbackPolicy {
    public static func shouldOfferChatGPTSwitch(
        afterProviderLimitText text: String,
        selectedModel: ClippyModel,
        isChatGPTAvailable: Bool
    ) -> Bool {
        selectedModel.backend == .claude
            && isChatGPTAvailable
            && ClippyUserFacingError.providerLimit(for: text) == .claude
    }
}
