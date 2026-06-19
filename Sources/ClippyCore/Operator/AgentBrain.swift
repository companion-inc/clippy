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

/// One streamed chunk from a brain turn.
public enum AgentStreamChunk: Sendable {
    case status(String)
    case partial(String)
    case partialMessage(text: String, id: String)
    case final(AgentTurn)
}

/// JSON Schema passed through a brain's native structured-output surface.
public struct AgentOutputSchema: @unchecked Sendable {
    public let jsonObject: [String: Any]

    public init(jsonObject: [String: Any]) {
        self.jsonObject = jsonObject
    }
}

/// A local conversation brain Clippy can chat through. Clippy is the only product shell;
/// this protocol must not grow selectable characters or per-character backends.
public protocol AgentBrain: Actor {
    func prepare() async
    func send(_ message: String) async -> AgentTurn
    func send(_ message: String, localImagePaths: [String]) async -> AgentTurn
    /// Streams the reply as it is generated. The default yields just the final
    /// `send` result; local CLI adapters override it with real token streaming.
    nonisolated func stream(_ message: String) -> AsyncStream<AgentStreamChunk>
    nonisolated func stream(_ message: String, localImagePaths: [String]) -> AsyncStream<AgentStreamChunk>
}

public protocol StructuredOutputAgentBrain: AgentBrain {
    func sendStructured(
        _ message: String,
        localImagePaths: [String],
        outputSchema: AgentOutputSchema
    ) async -> AgentTurn
}

public extension StructuredOutputAgentBrain {
    func sendStructured(_ message: String, outputSchema: AgentOutputSchema) async -> AgentTurn {
        await sendStructured(message, localImagePaths: [], outputSchema: outputSchema)
    }
}

public extension AgentBrain {
    func prepare() async {}

    func send(_ message: String, localImagePaths _: [String]) async -> AgentTurn {
        await send(message)
    }

    nonisolated func stream(_ message: String) -> AsyncStream<AgentStreamChunk> {
        AsyncStream { continuation in
            Task {
                let turn = await self.send(message)
                continuation.yield(.final(turn))
                continuation.finish()
            }
        }
    }

    nonisolated func stream(_ message: String, localImagePaths _: [String]) -> AsyncStream<AgentStreamChunk> {
        stream(message)
    }
}
