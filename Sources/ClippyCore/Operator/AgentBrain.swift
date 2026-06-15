import Foundation

/// One reply from a local agent CLI turn.
public struct AgentTurn: Sendable {
    public let text: String
    public let isError: Bool
    public let costUSD: Double?

    public init(text: String, isError: Bool, costUSD: Double? = nil) {
        self.text = text
        self.isError = isError
        self.costUSD = costUSD
    }
}

/// A local conversation brain the app can chat through. Mascot selection is a
/// shell/theme choice; it must not fork the chat backend or conversation.
public protocol AgentBrain: Actor {
    func send(_ message: String) async -> AgentTurn
}
