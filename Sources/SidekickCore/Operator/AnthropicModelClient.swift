import Foundation

/// Real assistant brain: drives the Anthropic Messages API with a tool loop.
///
/// The surrounding `AssistantLoop` calls `nextTurn` repeatedly, accumulating
/// `ToolResult` observations. This client is stateful across those calls within
/// one run: it keeps the full message history (user text, assistant tool_use
/// turns, tool_result turns) so the model sees a coherent conversation.
public actor AnthropicModelClient: AssistantModelClient {
    public struct ToolSpec: Sendable {
        public let name: String
        public let description: String
        public let inputSchema: [String: Any]

        public init(name: String, description: String, inputSchema: [String: Any]) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
        }
    }

    private let apiKey: String
    private let model: String
    private let system: String
    private let tools: [ToolSpec]
    private let urlSession: URLSession

    // Conversation state, built up across nextTurn calls.
    private var messages: [[String: Any]] = []
    private var seenObservationIDs: Set<UUID> = []
    private var pendingToolUseByInvocation: [UUID: String] = [:]
    private var didSeedUserText = false

    public init(
        apiKey: String,
        model: String = "claude-opus-4-8",
        system: String,
        tools: [ToolSpec],
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.system = system
        self.tools = tools
        self.urlSession = urlSession
    }

    public func nextTurn(_ request: AssistantTurnRequest) async throws -> AssistantTurnResponse {
        if !didSeedUserText {
            messages.append(["role": "user", "content": request.rawText])
            didSeedUserText = true
        }

        // Fold any newly-arrived tool results into the conversation as a single
        // user turn of tool_result blocks.
        let fresh = request.observations.filter { !seenObservationIDs.contains($0.invocationID) }
        if !fresh.isEmpty {
            var blocks: [[String: Any]] = []
            for result in fresh {
                seenObservationIDs.insert(result.invocationID)
                let toolUseID = pendingToolUseByInvocation[result.invocationID] ?? result.invocationID.uuidString
                blocks.append([
                    "type": "tool_result",
                    "tool_use_id": toolUseID,
                    "content": result.summary,
                    "is_error": result.status == .failed,
                ])
            }
            messages.append(["role": "user", "content": blocks])
        }

        let response = try await callMessages()
        return parse(response)
    }

    // MARK: - API call

    private func callMessages() async throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": messages,
        ]
        if !tools.isEmpty {
            // The API restricts tool names to [a-zA-Z0-9_-]; our internal names
            // are dotted (shell.exec), so swap separators at the wire boundary.
            body["tools"] = tools.map { spec in
                [
                    "name": Self.apiToolName(spec.name),
                    "description": spec.description,
                    "input_schema": spec.inputSchema,
                ] as [String: Any]
            }
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await urlSession.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw AnthropicModelClientError.httpError(detail)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicModelClientError.malformedResponse
        }
        return json
    }

    // MARK: - Response parsing

    private func parse(_ response: [String: Any]) -> AssistantTurnResponse {
        // Echo the assistant turn back into history so the next round is coherent.
        if let content = response["content"] {
            messages.append(["role": "assistant", "content": content])
        }

        let content = response["content"] as? [[String: Any]] ?? []
        var finalText: String? = nil
        var toolCalls: [ToolInvocation] = []

        for block in content {
            switch block["type"] as? String {
            case "text":
                let text = block["text"] as? String ?? ""
                finalText = (finalText.map { $0 + "\n" } ?? "") + text
            case "tool_use":
                guard let apiName = block["name"] as? String else {
                    continue
                }
                let name = internalToolName(forAPIName: apiName)
                let toolUseID = block["id"] as? String ?? UUID().uuidString
                let rawInput = block["input"] as? [String: Any] ?? [:]
                let invocation = ToolInvocation(name: name, arguments: convert(rawInput))
                pendingToolUseByInvocation[invocation.id] = toolUseID
                toolCalls.append(invocation)
            default:
                break
            }
        }

        // If the model both spoke and called tools, the loop should execute the
        // tools first, so only surface finalText when there are no tool calls.
        if !toolCalls.isEmpty {
            return AssistantTurnResponse(finalText: nil, toolCalls: toolCalls)
        }
        return AssistantTurnResponse(finalText: finalText, toolCalls: [])
    }

    private static func apiToolName(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_")
    }

    private func internalToolName(forAPIName apiName: String) -> String {
        tools.first { Self.apiToolName($0.name) == apiName }?.name ?? apiName
    }

    private func convert(_ raw: [String: Any]) -> [String: ToolValue] {
        var out: [String: ToolValue] = [:]
        for (key, value) in raw {
            out[key] = ToolValue(any: value)
        }
        return out
    }
}

public enum AnthropicModelClientError: Error, LocalizedError {
    case httpError(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case let .httpError(detail):
            return "Anthropic API error: \(detail)"
        case .malformedResponse:
            return "Anthropic API returned an unexpected response."
        }
    }
}

private extension ToolValue {
    init(any: Any) {
        switch any {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Double:
            self = .number(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as [Any]:
            self = .array(value.map { ToolValue(any: $0) })
        case let value as [String: Any]:
            self = .object(value.mapValues { ToolValue(any: $0) })
        default:
            self = .null
        }
    }
}
